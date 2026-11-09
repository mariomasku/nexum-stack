# ===========================================================================
# Docker con su propio Apache: un proyecto en varias versiones de PHP a la vez, sin LAMPP
# ===========================================================================
# Desde la 1.56 los proyectos nuevos en Docker no pasan por el Apache de LAMPP: Docker tiene el suyo
# (nexum-web, la imagen oficial de Apache) en otra direccion de este equipo (127.0.0.2 por defecto:
# DOCKER_WEB_FILE), asi que funcionan con LAMPP parado o con cualquier version activa. Lleva las mismas
# reglas de seguridad que LAMPP (las de UNKNOWN_HOST_VHOST: los ficheros que no se sirven y la barrera
# entre webs) y lee los .htaccess de cada proyecto. Los .php los pasa al contenedor de cada version de
# PHP (nexum-<proyecto>-php83, con la imagen nexum-php de siempre: ninguna imagen mas) por la red
# interna de Docker (nexum), sin puertos abiertos fuera. Las BBDD van en una MariaDB comun por version
# de MariaDB (nexum-mariadb-11-8), cada proyecto con su BBDD y su usuario, y hay un solo phpMyAdmin
# (https://pma.docker.local, con su pantalla de acceso). Un proyecto puede tener varias versiones de
# PHP a la vez con la misma BBDD: en WordPress, cada una con su dominio (<proyecto>-php83.docker.local,
# su wp-config.php del contenedor lo lleva); una tienda PrestaShop guarda su dominio en la BBDD, asi que
# va con uno solo (<proyecto>.docker.local) y la version que se elija. Un certificado propio para
# *.docker.local, que no es de una CA: no vale para ninguna otra web. Los proyectos de antes (con
# LAMPP delante) siguen igual hasta que se pasan (docker-pasar)
# (httpd fijado por su huella: la etiqueta 2.4 la puede mover cualquiera que llegue a esa cuenta de
# Docker Hub. Es la 2.4.69, Debian trixie, del 21/10/2026; para otra: docker buildx imagetools inspect)
DOCKER_WEB_IMAGE="httpd:2.4.69@sha256:a30cd4cd57f3f3c3be9b2d16384d2488839996bb14c67df2b51f1ecbb3e584a1"
DOCKER_WEB_DIR=$DOCKER_DIR/web
DOCKER_WEB_FILE="$DOCKER_DIR/web.conf"
# (los puertos de menos de 1024 son de root: con Docker sin root hay que bajar ese limite una vez)
DOCKER_SYSCTL=${LVM_DOCKER_SYSCTL:-/etc/sysctl.d/60-nexum-docker.conf}

#@incluir comun/docker-su-propio-apache/docker_web_get.sh
# ¿Puede Docker sin root abrir sus puertos? (el limite de los puertos de root, ip_unprivileged_port_start)
function docker_web_ports_ok() {
    local start low http https
    start=$(cat "${LVM_PORT_START_FILE:-/proc/sys/net/ipv4/ip_unprivileged_port_start}" 2> /dev/null || echo 1024)
    http=$(docker_web_get HTTP) https=$(docker_web_get HTTPS)
    low=$http
    [ "$https" -lt "$low" ] && low=$https
    [ "$low" -ge "$start" ]
}

#@incluir comun/docker-su-propio-apache/docker_maria_name.sh
# Certificado propio de *.docker.local (no es de una CA: solo vale para esos dominios), en una carpeta
# solo tuya: el Apache del contenedor lo lee como el root del contenedor, que en Docker sin root eres tu
function docker_web_cert() {
    local c=$DOCKER_WEB_DIR/certs
    if [ -s "$c/docker.local.crt" ] && [ -s "$c/docker.local.key" ]; then
        openssl x509 -in "$c/docker.local.crt" -noout -text 2> /dev/null | grep -q 'DNS:\*\.docker\.test' && return 0
        [ "$DRY" -eq 1 ] || rm -f "$c/docker.local.crt" "$c/docker.local.key"
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] certificado propio de *.docker.local en $c"
        return 0
    fi
    mkdir -p -m 700 "$DOCKER_DIR" "$DOCKER_WEB_DIR" "$c" || return 1
    if ! ( umask 077; openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=docker.local" \
            -addext "basicConstraints=critical,CA:FALSE" -addext "extendedKeyUsage=serverAuth" \
            -addext "subjectAltName=DNS:docker.local,DNS:*.docker.local,DNS:docker.test,DNS:*.docker.test" \
            -keyout "$c/docker.local.key" -out "$c/docker.local.crt" > /dev/null 2>&1 ); then
        rm -f "$c/docker.local.key" "$c/docker.local.crt"
        echo "No se ha podido crear el certificado de *.docker.local"
        return 1
    fi
    echo "Certificado propio de *.docker.local y *.docker.test (solo vale para esos dominios)"
}

# Chrome, Chromium y Firefox aceptan sin aviso el certificado de *.docker.local: va a sus almacenes
# con confianza P (la de un servidor, no la de una CA), como los de los proyectos de LAMPP
function docker_web_trust() {
    local crt=$DOCKER_WEB_DIR/certs/docker.local.crt nick="lvm-instalador docker.local" d i n=0
    # (en las pruebas, nunca en los navegadores de verdad)
    [ -n "$TEST_DIR" ] && return 0
    [ -f "$crt" ] || [ "$DRY" -eq 1 ] || return 0
    if ! command -v certutil > /dev/null; then
        echo "Para que Chrome y Firefox acepten *.docker.local sin aviso falta certutil: sudo apt install libnss3-tools"
        return 0
    fi
    for d in "$HOME/.pki/nssdb" "$HOME"/snap/chromium/current/.pki/nssdb "$HOME"/.mozilla/firefox/*/ \
             "$HOME"/snap/firefox/common/.mozilla/firefox/*/; do
        d=${d%/}
        [ -f "$d/cert9.db" ] || continue
        # (el de antes, si el certificado se ha rehecho: con el mismo nombre)
        for i in 1 2 3 4 5; do
            no_tty certutil -L -d "sql:$d" -n "$nick" > /dev/null 2>&1 || break
            run no_tty certutil -D -d "sql:$d" -n "$nick" || break
            [ "$DRY" -eq 0 ] || break
        done
        run no_tty certutil -A -d "sql:$d" -n "$nick" -t "P,," -i "$crt" && n=$((n + 1))
    done
    [ $n -gt 0 ] && echo "El navegador acepta el certificado de *.docker.local (si Chrome estaba abierto, cierralo y vuelve a abrirlo)"
    return 0
}

#@incluir comun/docker-su-propio-apache/docker_web_hosts.sh
# Reglas de seguridad de todas las webs, las mismas que en LAMPP (de UNKNOWN_HOST_VHOST: ficheros que
# no se sirven, CORS y la barrera entre webs, si esta encendida)
function docker_web_security() {
    local text="# Configuracion, repositorios${UNKNOWN_HOST_VHOST#*$'\n'# Configuracion, repositorios}"
    if cross_site_on; then
        printf '%s\n' "$text"
    else
        awk '/^# >>> barrera entre webs/ { s = 1 } !s { print } /^# <<< barrera entre webs/ { s = 0 }' <<< "$text"
    fi
}

# Vhosts de un proyecto en el Apache de Docker: http lleva a https, y en https la carpeta del proyecto
# (la misma ruta que en su contenedor de PHP) con los .php a su version de PHP. Una tienda, solo la
# version elegida (ACTIVA)
function docker_web_site() {
    local slug=$1 folder versions v dom
    folder=$(docker_conf "$slug" CARPETA)
    versions=$(docker_conf "$slug" PHP)
    [ "$(docker_conf "$slug" TIPO)" == ps ] && versions=$(docker_conf "$slug" ACTIVA)
    printf '# %s (%s)\n' "$slug" "$folder"
    for v in $versions; do
        dom=$(docker_web_domain "$slug" "$v")
        printf '<VirtualHost *:80>\n    ServerName %s\n    Redirect permanent / %s/\n</VirtualHost>\n' "$dom" "$(docker_web_url "$dom")"
        printf '<VirtualHost *:443>\n    ServerName %s\n    DocumentRoot "/opt/lampp/htdocs/%s"\n' "$dom" "$folder"
        printf '    SSLEngine on\n    SSLCertificateFile /certs/docker.local.crt\n    SSLCertificateKeyFile /certs/docker.local.key\n'
        # (con su PHP parado, por ejemplo al llevar horas sin visitas, lo dice en vez de un error sin mas.
        # Solo los errores del propio Apache: un 503 de la web, como el modo mantenimiento, pasa igual)
        printf '    ErrorDocument 502 "%s"\n    ErrorDocument 503 "%s"\n' "$DOCKER_STOPPED_MSG" "$DOCKER_STOPPED_MSG"
        printf '    <FilesMatch "\\.php$">\n        SetHandler "proxy:fcgi://%s:9000"\n    </FilesMatch>\n' "$(docker_web_container "$slug" "$v")"
        [ "$(docker_conf "$slug" TIPO)" == ps ] || docker_web_media "$folder"
        printf '</VirtualHost>\n'
    done
}

#@incluir comun/docker-su-propio-apache/docker_web_media.sh
function docker_web_write() {
    local d=$DOCKER_WEB_DIR p tmp pma_hosts="" v
    [ "$DRY" -eq 1 ] && return 0
    mkdir -p -m 700 "$DOCKER_DIR" "$d" || return 1
    tmp=$(mktemp -d "$d/.nexum-XXXXXX") || return 1
    mkdir -p "$tmp/sitios" || return 1
    docker_web_security > "$tmp/seguridad.conf" || return 1
    cat > "$tmp/httpd.conf" << 'EOF'
# Apache de Docker de lvm-instalador (se rehace solo: no se edita a mano)
ServerRoot "/usr/local/apache2"
Listen 80
Listen 443
LoadModule mpm_event_module modules/mod_mpm_event.so
# (en local basta un proceso con sus hilos: no tres esperando, como trae de fabrica)
StartServers 1
ServerLimit 4
ThreadsPerChild 25
MinSpareThreads 5
MaxSpareThreads 50
MaxRequestWorkers 100
LoadModule unixd_module modules/mod_unixd.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule authz_host_module modules/mod_authz_host.so
LoadModule authz_user_module modules/mod_authz_user.so
LoadModule authn_core_module modules/mod_authn_core.so
LoadModule authn_file_module modules/mod_authn_file.so
LoadModule auth_basic_module modules/mod_auth_basic.so
LoadModule access_compat_module modules/mod_access_compat.so
LoadModule mime_module modules/mod_mime.so
LoadModule log_config_module modules/mod_log_config.so
LoadModule env_module modules/mod_env.so
LoadModule setenvif_module modules/mod_setenvif.so
LoadModule headers_module modules/mod_headers.so
LoadModule expires_module modules/mod_expires.so
LoadModule filter_module modules/mod_filter.so
LoadModule deflate_module modules/mod_deflate.so
LoadModule rewrite_module modules/mod_rewrite.so
LoadModule dir_module modules/mod_dir.so
LoadModule alias_module modules/mod_alias.so
LoadModule version_module modules/mod_version.so
LoadModule socache_shmcb_module modules/mod_socache_shmcb.so
LoadModule ssl_module modules/mod_ssl.so
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so
LoadModule proxy_http_module modules/mod_proxy_http.so
# (los procesos que sirven las webs, con un usuario sin privilegios del contenedor: leen los ficheros
# del proyecto, no los cambian. El PHP va en su contenedor, que si los puede cambiar)
User daemon
Group daemon
ServerName docker.local
ServerSignature Off
ServerTokens Prod
ErrorLog /proc/self/fd/2
LogLevel warn
LogFormat "%v %h %t \"%r\" %>s %b" nexum
CustomLog /proc/self/fd/1 nexum
TypesConfig conf/mime.types
DirectoryIndex index.php index.html index.htm
Timeout 300
ProxyTimeout 300
SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
SSLSessionCache "shmcb:/usr/local/apache2/logs/ssl_scache(512000)"
<Directory />
    AllowOverride None
    Require all denied
</Directory>
<Directory "/opt/lampp/htdocs">
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
Include conf/nexum/seguridad.conf
IncludeOptional conf/nexum/sitios/*.conf
EOF
    # (el primero: los dominios sin proyecto, con un 403)
    { printf '# Dominios sin ningun proyecto en Docker\n'
      for p in 80 443; do
          printf '<VirtualHost *:%s>\n    ServerName docker.local\n' "$p"
          [ $p == 443 ] && printf '    SSLEngine on\n    SSLCertificateFile /certs/docker.local.crt\n    SSLCertificateKeyFile /certs/docker.local.key\n'
          printf '    <Location />\n        Require all denied\n        ErrorDocument 403 "Este dominio no tiene ningun proyecto en Docker (lvm-instalador)"\n    </Location>\n</VirtualHost>\n'
      done; } > "$tmp/sitios/000-defecto.conf"
    # phpMyAdmin: su contenedor, por https://pma.docker.local o pma.docker.test (con su pantalla de acceso)
    { printf '<VirtualHost *:80>\n    ServerName %s\n    Redirect permanent / %s/\n</VirtualHost>\n' "$(docker_web_pma)" "$(docker_web_url "$(docker_web_pma)")"
      printf '<VirtualHost *:443>\n    ServerName %s\n' "$(docker_web_pma)"
      printf '    SSLEngine on\n    SSLCertificateFile /certs/docker.local.crt\n    SSLCertificateKeyFile /certs/docker.local.key\n'
      printf '    ProxyPass / http://nexum-pma/\n    ProxyPassReverse / http://nexum-pma/\n</VirtualHost>\n'; } > "$tmp/sitios/001-phpmyadmin.conf"
    for p in $(docker_web_projects); do
        docker_web_site "$p" > "$tmp/sitios/$p.conf" || return 1
    done
    for v in $(docker_maria_versions); do pma_hosts+=",$(docker_maria_name "$v")"; done
    pma_hosts=${pma_hosts#,}
    { printf 'name: nexum-web\nservices:\n'
      printf '  web:\n    image: %s\n    container_name: nexum-web\n    restart: "no"\n' "$DOCKER_WEB_IMAGE"
      printf '    ports:\n      - "%s:%s:80"\n      - "%s:%s:443"\n' "$(docker_web_get IP)" "$(docker_web_get HTTP)" "$(docker_web_get IP)" "$(docker_web_get HTTPS)"
      printf '    volumes:\n      - "%s:/opt/lampp/htdocs:ro"\n' "$HTDOCS_DIR"
      printf '      - "./conf:/usr/local/apache2/conf/nexum:ro"\n      - "./certs:/certs:ro"\n'
      printf '    command: ["httpd-foreground", "-f", "%s"]\n    networks: [nexum]\n' "$DOCKER_WEB_CONF"
      printf '  pma:\n    image: %s\n    container_name: nexum-pma\n    restart: "no"\n    environment:\n' "$DOCKER_PMA_IMAGE"
      printf '      PMA_HOSTS: "%s"\n      PMA_ABSOLUTE_URI: "%s/"\n      UPLOAD_LIMIT: 64M\n    networks: [nexum]\n' \
          "${pma_hosts:-$(docker_maria_name 11.8)}" "$(docker_web_url "$(docker_web_pma)")"
      printf 'networks:\n  nexum:\n    external: true\n    name: nexum\n'; } > "$tmp/compose.yaml"
    chmod -R go-rwx "$tmp"
    # (dentro de conf, que no se cambia: los ficheros y, de golpe, la carpeta de los vhosts)
    mkdir -p -m 700 "$d/conf" || return 1
    rm -rf "$d/conf/sitios.antes"
    [ -d "$d/conf/sitios" ] && mv "$d/conf/sitios" "$d/conf/sitios.antes"
    mv "$tmp/sitios" "$d/conf/sitios" && mv -f "$tmp/seguridad.conf" "$tmp/httpd.conf" "$d/conf/" \
        && mv -f "$tmp/compose.yaml" "$d/compose.yaml" || return 1
    rm -rf "$tmp" "$d/conf/sitios.antes"
}

# Estado del Apache de Docker: marcha, parado o nuevo (sin contenedor)
function docker_web_state() {
    local s
    s=$(dk ps -a --filter name='^nexum-web$' --format '{{.State}}' 2> /dev/null | head -1)
    case $s in running) echo marcha ;; "") echo nuevo ;; *) echo parado ;; esac
}

# Arranca el Apache de Docker y su phpMyAdmin (con su configuracion al dia, su certificado y la linea de
# pma.docker.local en hosts). Si ya estaba en marcha, recarga su configuracion sin cortar nada
function docker_web_up() {
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] Apache de Docker (nexum-web) en $(docker_web_get IP), puertos $(docker_web_get HTTP) y $(docker_web_get HTTPS)"
        return 0
    fi
    if ! docker_web_ports_ok; then
        echo "Docker sin root aun no puede usar los puertos $(docker_web_get HTTP) y $(docker_web_get HTTPS)."
        echo "Pulsa «Permitir» en Configuracion, Docker (o: lvm-instalador docker-web permitir), o elige otros puertos."
        return 1
    fi
    docker_web_cert && docker_web_write && docker_net || return 1
    docker_web_hosts poner "$(docker_web_pma)" || return 1
    local was
    was=$(docker_web_state)
    dk compose --project-directory "$DOCKER_WEB_DIR" -f "$DOCKER_WEB_DIR/compose.yaml" up -d || return 1
    [ "$was" == marcha ] && docker_web_reload --sin-escribir
    return 0
}

#@incluir comun/docker-su-propio-apache/docker_web_reload.sh
# docker-web [estado] | puertos <ip> <http> <https> | permitir | arrancar | parar | confiar
#   estado: W|direccion|http|https|estado (marcha, parado o nuevo)|puertos permitidos (1/0)
function docker_web_command() {
    case ${1:-estado} in
        estado)
            echo "W|$(docker_web_get IP)|$(docker_web_get HTTP)|$(docker_web_get HTTPS)|$(docker_ready && docker_web_state || echo "?")|$(docker_web_ports_ok && echo 1 || echo 0)|$(docker_web_tld)|$(docker_dns_on && echo 1 || echo 0)" ;;
        dns) shift; docker_dns_command "$@" ;;
        puertos) docker_web_set "$2" "$3" "$4" ;;
        permitir) docker_web_allow ;;
        arrancar)
            docker_ready || { echo "Docker sin root no esta en marcha"; return 1; }
            docker_web_up ;;
        parar)
            [ "$DRY" -eq 1 ] && { echo "  [simulacion] Apache de Docker y phpMyAdmin parados"; return 0; }
            run dk compose --project-directory "$DOCKER_WEB_DIR" -f "$DOCKER_WEB_DIR/compose.yaml" stop ;;
        confiar) docker_web_trust ;;
        *) echo "Uso: lvm-instalador docker-web [estado] | puertos <ip> <http> <https> | permitir | arrancar | parar | confiar | dns activar|quitar"; return 1 ;;
    esac
}

# docker-web puertos <ip> <http> <https>: otra direccion (siempre de 127.x) u otros puertos. Con los de
# siempre (80 y 443) no puede ser 127.0.0.1: los usa el Apache de LAMPP. Los dominios de Docker pasan a
# la direccion nueva en /etc/hosts y el Apache de Docker se vuelve a crear. (Docker sin root no deja que
# dos contenedores publiquen el mismo numero de puerto aunque sea en otra direccion: no puede coincidir
# con el de un phpMyAdmin de un proyecto de antes, 28080 en adelante)
function docker_web_set() {
    local ip=$1 http=$2 https=$3 p domains=()
    if ! docker_web_valid_ip "$ip"; then
        echo "Direccion no valida: $ip (tiene que ser de este equipo: 127.x.x.x, como 127.0.0.2)"
        return 1
    fi
    for p in "$http" "$https"; do
        [[ "$p" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$p" -le 65535 ] || { echo "Puerto no valido: $p"; return 1; }
    done
    [ "$http" != "$https" ] || { echo "Los puertos HTTP y HTTPS tienen que ser distintos"; return 1; }
    if [ "$ip" == 127.0.0.1 ] && { [ "$http" == 80 ] || [ "$https" == 443 ] || [ "$http" == 443 ] || [ "$https" == 80 ]; }; then
        echo "En 127.0.0.1 los puertos 80 y 443 son del Apache de LAMPP: usa otra direccion (127.0.0.2) u otros puertos"
        return 1
    fi
    echo "Apache de Docker: $ip, puertos $http (http) y $https (https)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] se guarda en $DOCKER_WEB_FILE y los dominios de Docker pasan a $ip en $HOSTS_FILE"
        return 0
    fi
    mkdir -p -m 700 "$DOCKER_DIR" || return 1
    docker_web_conf_write "$ip" "$http" "$https" "$(docker_web_tld)" "$(docker_web_get DNS)" || return 1
    docker_web_ports_ok || echo "Aviso: Docker sin root aun no puede usar esos puertos: pulsa «Permitir» (lvm-instalador docker-web permitir)"
    [ -d "$DOCKER_WEB_DIR" ] || return 0
    sudo_first || return 1
    # (con el DNS comodin, este responde con la direccion nueva)
    docker_dns_on && { docker_dns_install || return 1; }
    for p in $(docker_web_projects); do
        mapfile -t -O "${#domains[@]}" domains < <(docker_web_domains "$p")
    done
    docker_web_hosts poner "$(docker_web_pma)" "${domains[@]}" || return 1
    if docker_ready && [ "$(docker_web_state)" != nuevo ] && docker_web_ports_ok; then
        docker_web_up || return 1
    else
        docker_web_write
    fi
    echo "Listo: los proyectos de Docker se abren en $(docker_web_url "<proyecto>.$(docker_web_tld)")"
}

# docker-web permitir: Docker sin root puede abrir los puertos del Apache de Docker. Linux deja los de
# menos de 1024 solo a root; se baja ese limite (net.ipv4.ip_unprivileged_port_start, en DOCKER_SYSCTL)
# hasta el mas bajo de los dos. Desde entonces cualquier programa del equipo puede abrir esos puertos
# (en un equipo de desarrollo, como cualquier puerto alto): pide la contraseña de administrador
function docker_web_allow() {
    local http https low
    http=$(docker_web_get HTTP) https=$(docker_web_get HTTPS)
    low=$http
    [ "$https" -lt "$low" ] && low=$https
    if docker_web_ports_ok; then
        echo "Docker sin root ya puede usar los puertos $http y $https"
        return 0
    fi
    echo "Docker sin root podra usar los puertos desde el $low (net.ipv4.ip_unprivileged_port_start en $DOCKER_SYSCTL)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] sudo tee $DOCKER_SYSCTL y sudo sysctl -p $DOCKER_SYSCTL"
        return 0
    fi
    sudo_first || return 1
    printf '# lvm-instalador: Docker sin root puede usar los puertos del Apache de Docker\nnet.ipv4.ip_unprivileged_port_start = %s\n' "$low" \
        | sudo tee "$DOCKER_SYSCTL" > /dev/null && sudo sysctl -q -p "$DOCKER_SYSCTL" || return 1
    docker_web_ports_ok || { echo "No se ha podido cambiar el limite de los puertos"; return 1; }
    echo "Listo: Docker sin root ya puede usar los puertos $http y $https"
}

# El DNS en Linux: un servicio del sistema con un usuario sin privilegios que se crea cada vez
# (DynamicUser) y systemd-resolved, que le manda solo lo de docker.test (Domains=~docker.test: un DNS con
# solo dominios de enrutado no recibe ninguna otra pregunta). Todo de root
DOCKER_DNS_SCRIPT=${LVM_DNS_SCRIPT:-/usr/local/lib/nexum/nexum-dns.py}
DOCKER_DNS_UNIT=${LVM_DNS_UNIT:-/etc/systemd/system/nexum-dns.service}
DOCKER_DNS_RESOLVED=${LVM_DNS_RESOLVED:-/etc/systemd/resolved.conf.d/60-nexum-docker.conf}
function docker_dns_install() {
    local ip d
    ip=$(docker_web_get IP)
    [ "$DRY" -eq 1 ] && return 0
    for d in "$(dirname "$DOCKER_DNS_SCRIPT")" "$(dirname "$DOCKER_DNS_RESOLVED")"; do
        sudo install -d -m 755 "$d" || return 1
    done
    printf '%s\n' "$DOCKER_DNS_PY" | sudo tee "$DOCKER_DNS_SCRIPT" > /dev/null && sudo chmod 644 "$DOCKER_DNS_SCRIPT" || return 1
    printf '%s\n' "# Nexum Dev Stack: DNS de *.docker.test, solo en 127.0.0.1 (lo pone lvm-instalador docker-web dns activar)" \
        "[Unit]" "Description=Nexum Dev Stack: DNS de *.docker.test" "After=network.target" "" "[Service]" \
        "ExecStart=/usr/bin/python3 -I $DOCKER_DNS_SCRIPT 127.0.0.1 $DOCKER_DNS_PORT docker.test $ip" \
        "DynamicUser=yes" "ProtectSystem=strict" "ProtectHome=yes" "PrivateTmp=yes" "PrivateDevices=yes" "NoNewPrivileges=yes" \
        "RestrictAddressFamilies=AF_INET AF_INET6" "CapabilityBoundingSet=" "Restart=on-failure" "" "[Install]" "WantedBy=multi-user.target" \
        | sudo tee "$DOCKER_DNS_UNIT" > /dev/null || return 1
    printf '%s\n' "# Nexum Dev Stack: lo de docker.test, al DNS de Nexum (y nada mas)" "[Resolve]" \
        "DNS=127.0.0.1:$DOCKER_DNS_PORT" "Domains=~docker.test" | sudo tee "$DOCKER_DNS_RESOLVED" > /dev/null || return 1
    sudo systemctl daemon-reload && sudo systemctl enable nexum-dns.service > /dev/null 2>&1 \
        && sudo systemctl restart nexum-dns.service && sudo systemctl restart systemd-resolved
}

function docker_dns_uninstall() {
    [ "$DRY" -eq 1 ] && return 0
    sudo systemctl disable --now nexum-dns.service > /dev/null 2>&1
    sudo rm -f "$DOCKER_DNS_UNIT" "$DOCKER_DNS_RESOLVED" "$DOCKER_DNS_SCRIPT"
    sudo systemctl daemon-reload
    sudo systemctl restart systemd-resolved
}

# DNS comodin de *.docker.test (docker-web dns activar): un DNS minimo, solo en 127.0.0.1, que contesta
# la direccion del Apache de Docker a cualquier <algo>.docker.test y rechaza todo lo demas. Asi los
# dominios de Docker ya no van en /etc/hosts (ni piden la contraseña al añadir proyectos o versiones).
# Solo para *.docker.test: web.local, los proyectos de siempre y los dominios falseados de las tiendas
# siguen en /etc/hosts, que se mira antes. (.local es de mDNS: un DNS para *.docker.local no se
# consultaria nunca)
DOCKER_DNS_PORT=5354
DOCKER_DNS_PY=$(cat <<'DNSPY'
# DNS de *.docker.test de Nexum Dev Stack (lo pone lvm-instalador docker-web dns activar: no se edita a
# mano). nexum-dns.py <direccion> <puerto> <zona> <ip>: contesta <ip> a la zona y a lo que acabe en ella
# (registros A; los demas tipos, sin datos) y REFUSED a todo lo demas. UDP y TCP, sin estado
import socket, socketserver, struct, sys, threading

HOST, PORT, ZONE, IP = sys.argv[1], int(sys.argv[2]), sys.argv[3].lower().strip("."), sys.argv[4]
ADDR = socket.inet_aton(IP)


def answer(q):
    if len(q) < 17:
        return None
    tid, flags, qd = struct.unpack(">HHH", q[:6])
    # (solo preguntas normales, de una en una)
    if flags & 0x8000 or (flags >> 11) & 0xF or qd != 1:
        return None
    i, labels = 12, []
    while True:
        if i >= len(q):
            return None
        n = q[i]
        i += 1
        if n == 0:
            break
        if n > 63 or i + n > len(q):
            return None
        labels.append(q[i:i + n].decode("ascii", "replace").lower())
        i += n
    if i + 4 > len(q):
        return None
    qtype, qclass = struct.unpack(">HH", q[i:i + 4])
    question = q[12:i + 4]
    name = ".".join(labels)
    rd = flags & 0x0100
    if name != ZONE and not name.endswith("." + ZONE):
        return struct.pack(">HHHHHH", tid, 0x8000 | rd | 0x0080 | 5, 1, 0, 0, 0) + question
    if qtype == 1 and qclass == 1:
        rr = b"\xc0\x0c" + struct.pack(">HHIH", 1, 1, 60, 4) + ADDR
        return struct.pack(">HHHHHH", tid, 0x8400 | rd | 0x0080, 1, 1, 0, 0) + question + rr
    return struct.pack(">HHHHHH", tid, 0x8400 | rd | 0x0080, 1, 0, 0, 0) + question


class UDP(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        out = answer(data)
        if out:
            sock.sendto(out, self.client_address)


class TCP(socketserver.StreamRequestHandler):
    def handle(self):
        self.connection.settimeout(5)
        try:
            size = struct.unpack(">H", self.rfile.read(2))[0]
            out = answer(self.rfile.read(size))
            if out:
                self.wfile.write(struct.pack(">H", len(out)) + out)
        except (OSError, struct.error):
            pass


class UDPServer(socketserver.ThreadingMixIn, socketserver.UDPServer):
    daemon_threads = True
    allow_reuse_address = True


class TCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True


udp = UDPServer((HOST, PORT), UDP)
tcp = TCPServer((HOST, PORT), TCP)
threading.Thread(target=tcp.serve_forever, daemon=True).start()
udp.serve_forever()
DNSPY
)

#@incluir comun/docker-su-propio-apache/docker_dns_works.sh
# Configuracion de una version de PHP de un proyecto para su contenedor (config-83.php: su BBDD en la
# MariaDB comun y, en WordPress, el dominio de esa version). Nada si el proyecto no la tiene
function docker_web_config() {
    local slug=$1 v=$2 dir=$DOCKER_DIR/$1 rel
    # (el dominio, con el puerto si no es el 443: WordPress lo pone en sus enlaces)
    local url
    url=$(docker_web_url "$(docker_web_domain "$slug" "$v")")
    local folder hosts
    folder=$(docker_conf "$slug" CARPETA)
    # (las de la web en local: web.local y su dominio propio, si tiene. En lo que devuelve, las del contenedor)
    hosts="$PROJECT_VHOST $(custom_domain "$folder" 2> /dev/null)"
    local server
    # (la BBDD: la de una version LAMPP en vivo, por su puente, o la de la MariaDB comun)
    if [ -n "$(docker_conf "$slug" LAMPP_BD)" ]; then
        server=$(lampp_bd_bridge "$(docker_conf "$slug" LAMPP_BD)")
    else
        server=$(docker_maria_name "$(docker_conf "$slug" MARIADB)")
    fi
    rel=$(LVM_DOMINIOS_LOCALES=$hosts docker_project_config "$folder" "$dir" "${url#https://}" \
        "$(docker_conf "$slug" BBDD)" "$(docker_conf "$slug" USUARIO)" "$(sed -n 's/^DB_PASS=//p' "$dir/.env")" \
        "$server") || return 1
    [ -n "$rel" ] || return 0
    # (si ya estaba, se cambia en su sitio: el contenedor la tiene montada y la ve al momento)
    if [ -f "$dir/config-${v//./}.php" ]; then
        cat "$dir/config.php" > "$dir/config-${v//./}.php" && rm -f "$dir/config.php"
    else
        mv -f "$dir/config.php" "$dir/config-${v//./}.php"
    fi
}

# compose.yaml de un proyecto: un servicio por version de PHP (php83...), con la imagen nexum-php de esa
# version, PHP-FPM en el puerto 9000 de la red interna (fpm.conf), la carpeta en la misma ruta que ve
# el Apache de Docker, su configuracion de solo lectura encima de la del proyecto y, en PrestaShop 1.7
# o posterior, su cache en un volumen propio de cada version
function docker_web_compose() {
    local slug=$1 dir=$DOCKER_DIR/$1 folder rel v vv vols=""
    folder=$(docker_conf "$slug" CARPETA) rel=$(docker_conf "$slug" CONFIG)
    { printf 'name: nexum-%s\nservices:\n' "$slug"
      for v in $(docker_conf "$slug" PHP); do
          vv=${v//./}
          printf '  php%s:\n    image: nexum-php:%s\n    container_name: %s\n    restart: "no"\n' "$vv" "$v" "$(docker_web_container "$slug" "$v")"
          printf '    command: ["php-fpm", "-R", "-F"]\n    volumes:\n'
          printf '      - "%s:/opt/lampp/htdocs/%s"\n' "$HTDOCS_DIR/$folder" "$folder"
          printf '      - "./fpm.conf:/usr/local/etc/php-fpm.d/zz-nexum.conf:ro"\n'
          [ -n "$rel" ] && [ -f "$dir/config-$vv.php" ] && printf '      - "./config-%s.php:/opt/lampp/htdocs/%s/%s:ro"\n' "$vv" "$folder" "$rel"
          if [ "$rel" == app/config/parameters.php ]; then
              printf '      - "cache-%s:/opt/lampp/htdocs/%s/var/cache"\n' "$vv" "$folder"
              vols+="  cache-$vv: {}"$'\n'
          fi
          printf '    networks: [nexum]\n'
      done
      [ -n "$vols" ] && printf 'volumes:\n%s' "$vols"
      printf 'networks:\n  nexum:\n    external: true\n    name: nexum\n'; } > "$dir/compose.yaml.nuevo" \
        && mv -f "$dir/compose.yaml.nuevo" "$dir/compose.yaml"
}

# Pool de PHP-FPM de los contenedores (fpm.conf): los procesos se abren al llegar peticiones (ondemand)
# y se cierran a los 20 s sin trabajo. Un proyecto en marcha sin usar gasta solo su proceso principal (unos
# MB), no dos o tres procesos esperando (100-200 MB, lo de fabrica de la imagen). Al arrancar se rehace
function docker_fpm_conf() {
    printf '[global]\nerror_log = /proc/self/fd/2\ndaemonize = no\n[www]\nuser = root\ngroup = root\nlisten = 9000\nclear_env = no\ncatch_workers_output = yes\npm = ondemand\npm.max_children = 10\npm.process_idle_timeout = 20s\npm.max_requests = 50\n'
}

# El fpm.conf del proyecto, al dia (los de antes de la 1.56.7, sin ondemand). Devuelve 0 si ha cambiado:
# sus contenedores se rehacen al arrancar (lo leen al empezar)
function docker_fpm_refresh() {
    local f=$DOCKER_DIR/$1/fpm.conf
    docker_fpm_conf | cmp -s - "$f" && return 1
    ( umask 077; docker_fpm_conf > "$f" )
}

#@incluir comun/docker-su-propio-apache/docker_web_services.sh
# docker-nuevo <carpeta> <php> <mariadb> [--bd <base> --desde <version LAMPP> | --volcado <fichero>]:
# proyecto en Docker con el Apache de Docker. Su BBDD (vacia, la de una version LAMPP o un volcado) va en
# la MariaDB comun de esa version, con su propio usuario. Mas versiones de PHP: docker-php-añadir
function docker_web_create() {
    local folder=${1%/} php=$2 maria=$3 db="" from="" dump="" slug dir tipo dbname user pass rel p live=0
    shift 3 2> /dev/null
    while [ $# -gt 0 ]; do
        case $1 in
            --en-vivo) live=1; shift ;;
            --bd|--desde|--volcado)
                [ -n "$2" ] || { echo "Falta el valor de $1"; return 1; }
                case $1 in --bd) db=$2 ;; --desde) from=$2 ;; --volcado) dump=$2 ;; esac
                shift 2 ;;
            *) echo "Opcion desconocida: $1"; return 1 ;;
        esac
    done
    if [ -z "$folder" ] || [ -z "$php" ] || [ -z "$maria" ]; then
        echo "Uso: lvm-instalador docker-nuevo <carpeta> <php> <mariadb> [--bd <base> --desde <version> | --volcado <fichero>]"
        return 1
    fi
    valid_project "$folder" || return 1
    [[ " $DOCKER_PHP_VERSIONS " == *" $php "* ]] || { echo "PHP $php no se ofrece en Docker ($DOCKER_PHP_VERSIONS)"; return 1; }
    [[ " $DOCKER_MARIADB_VERSIONS " == *" $maria "* ]] || { echo "MariaDB $maria no se ofrece en Docker ($DOCKER_MARIADB_VERSIONS)"; return 1; }
    if [ -n "$db" ]; then
        db_valid_name "$db" || return 1
    fi
    if [ -n "$from" ]; then
        [ -n "$db" ] && valid_version_name "$from" && [ -d "${TEST_DIR:-/opt}/lampp-$from" ] \
            || { echo "Con --desde hay que decir la base (--bd) y una version LAMPP que exista"; return 1; }
    elif [ -n "$db" ] && [ -z "$dump" ]; then
        echo "Con --bd hay que decir de que version LAMPP se copia (--desde)"
        return 1
    fi
    if [ -n "$dump" ] && { [ ! -f "$dump" ] || [ -L "$dump" ] || [ -n "$from" ]; }; then
        echo "El volcado tiene que ser un fichero (y sin --desde): $dump"
        return 1
    fi
    slug=$(docker_slug "$folder") && docker_valid_slug "$slug" || { echo "No se puede sacar un nombre corto de $folder"; return 1; }
    # (los nombres de lo comun no: la carpeta del Apache de Docker, las de las MariaDB y las del gestor)
    case $slug in web|bin|imagenes|mariadb-*) slug=$(cut -c1-31 <<< "$slug" | sed 's/-*$//')-proyecto ;; esac
    for p in $(docker_web_projects); do
        if [ "$(docker_conf "$p" CARPETA)" == "$folder" ]; then
            echo "$folder ya esta en Docker ($p): para otra version de PHP, lvm-instalador docker-php-añadir $p $php"
            return 1
        fi
    done
    dir=$DOCKER_DIR/$slug
    if [ -e "$dir" ]; then
        echo "Ya hay un proyecto en Docker con el nombre $slug (de antes, con LAMPP delante): pasalo con lvm-instalador docker-pasar $slug"
        return 1
    fi
    # shellcheck disable=SC2209  # (tipo=otro es un texto, no una orden)
    if is_prestashop "$folder"; then tipo=ps; elif is_wordpress "$folder"; then tipo=wp; else tipo=otro; fi
    if [ $live -eq 1 ]; then
        [ "$tipo" == wp ] && [ -n "$from" ] || { echo "--en-vivo: solo con un WordPress y su BBDD de una version LAMPP (--bd y --desde)"; return 1; }
    fi
    dbname=${db:-$(tr '-' '_' <<< "$slug")}
    user=$(cut -c1-32 <<< "nx_$dbname")
    echo "Proyecto en Docker: $folder con PHP $php y MariaDB $maria comun (BBDD $dbname)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $dir con la imagen nexum-php:$php, la BBDD $dbname en $(docker_maria_name "$maria") y $(docker_web_url "$( [ $tipo == ps ] && echo "$slug" || echo "$slug-php${php//./}").docker.local")"
        [ -n "$db" ] && echo "  [simulacion] copia de $db ${from:+de lampp-$from}${dump:+de $dump}"
        return 0
    fi
    docker_ready || { echo "Docker sin root no esta en marcha: instalalo o arrancalo en la pestaña Docker."; return 1; }
    if ! docker_web_ports_ok; then
        echo "Docker sin root aun no puede usar los puertos $(docker_web_get HTTP) y $(docker_web_get HTTPS): pulsa «Permitir» en"
        echo "Configuracion, Docker (o: lvm-instalador docker-web permitir), o elige otros puertos."
        return 1
    fi
    # La contraseña antes de cambiar nada (hosts): cancelarla deja todo como estaba. Con el DNS comodin no
    # se toca /etc/hosts: no hace falta
    docker_dns_on || sudo_first || return 1
    if [ $live -eq 1 ]; then
        docker_web_create_live "$folder" "$php" "$maria" "$from" "$slug" "$dir"
        return
    fi
    task_plan "Montando $folder en Docker" "MariaDB $maria común" "Imagen de PHP $php" "BBDD $dbname" "Apache de Docker" "Certificado en el navegador"
    task_step
    echo "1/5 MariaDB $maria comun"
    docker_maria_up "$maria" || return 1
    if [ "$(docker_maria_sql "$maria" -N -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$dbname'" < /dev/null 2> /dev/null | tr -d '\r')" != 0 ]; then
        echo "Ya hay una BBDD $dbname en la MariaDB $maria de Docker (de otro proyecto): elige otra o borra aquel proyecto"
        return 1
    fi
    mkdir -p -m 700 "$DOCKER_DIR" "$dir" || return 1
    pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
    for rel in wp-config.php app/config/parameters.php config/settings.inc.php; do
        [ -f "$HTDOCS_DIR/$folder/$rel" ] && [ ! -L "$HTDOCS_DIR/$folder/$rel" ] && break
        rel=""
    done
    ( umask 077
      printf 'DB_PASS=%s\n' "$pass" > "$dir/.env"
      printf 'MODO=web\nCARPETA=%s\nTIPO=%s\nPHP=%s\nACTIVA=%s\nMARIADB=%s\nBBDD=%s\nUSUARIO=%s\nCONFIG=%s\n' \
          "$folder" "$tipo" "$php" "$php" "$maria" "$dbname" "$user" "$rel" > "$dir/proyecto.conf"
      docker_fpm_conf > "$dir/fpm.conf" ) || return 1
    # (el dominio: el de la tienda o el de la version)
    docker_conf_set "$slug" DOMINIO "$(docker_web_domain "$slug" "$php")"
    docker_web_config "$slug" "$php" && docker_web_compose "$slug" || return 1
    task_step
    echo "2/5 Imagen de PHP $php"
    docker_php_image "$php" || { echo "No se ha podido preparar la imagen de PHP $php"; return 1; }
    task_step
    echo "3/5 BBDD $dbname"
    docker_maria_sql "$maria" << EOF || return 1
CREATE DATABASE \`$dbname\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$pass';
ALTER USER '$user'@'%' IDENTIFIED BY '$pass';
GRANT ALL PRIVILEGES ON \`$dbname\`.* TO '$user'@'%';
EOF
    if [ -n "$from" ] || [ -n "$dump" ]; then
        local tmp=$dump
        if [ -n "$from" ]; then
            mkdir -p -m 700 "$LOG_DIR" || return 1
            tmp=$(mktemp "$LOG_DIR/docker-$slug-XXXXXX") && mv -f "$tmp" "$tmp.sql.gz" && tmp=$tmp.sql.gz || return 1
            echo "Copiando $db de lampp-$from..."
            export_database "$db" "$tmp" "$from" || { rm -f "$tmp"; tmp=""; echo "No se ha podido descargar $db de lampp-$from: la BBDD queda vacia."; }
            db_temp_stop
        fi
        if [ -n "$tmp" ]; then
            { if [[ "$tmp" == *.gz ]]; then gzip -dc "$tmp"; else cat "$tmp"; fi; } \
                | docker_maria_sql "$maria" --binary-mode "$dbname" \
                || echo "Aviso: la carga de la BBDD ha dado errores (mira el registro)."
            [ -n "$from" ] && rm -f "$tmp"
            [ $tipo == ps ] && docker_web_ps_domain "$slug"
            local admin
            admin=$(docker_test_admin "$slug")
            grep -v '^A|' <<< "$admin" | grep .
            grep -q '^A|' <<< "$admin" && echo "Administrador de pruebas del panel: $TEST_ADMIN_USER, contraseña $TEST_ADMIN_PASS"
        fi
    fi
    task_step
    echo "4/5 Apache de Docker y $(docker_web_domain "$slug" "$php")"
    docker_web_hosts poner "$(docker_web_pma)" "$(docker_web_domain "$slug" "$php")" || return 1
    docker_web_up || return 1
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d "php${php//./}" || return 1
    task_step
    echo "5/5 Certificado en el navegador"
    docker_web_trust
    echo "Proyecto en Docker listo: $(docker_web_url "$(docker_web_domain "$slug" "$php")") (PHP $php). phpMyAdmin: $(docker_web_url "$(docker_web_pma)")"
}

# docker-nuevo ... --en-vivo: el proyecto sin BBDD en Docker, con la de esa version LAMPP en vivo (con el
# usuario y la contraseña de su wp-config.php)
function docker_web_create_live() {
    local folder=$1 php=$2 maria=$3 from=$4 slug=$5 dir=$6 creds owner
    creds=$(lampp_bd_creds "$folder") || { echo "No se puede leer el usuario y la base del wp-config.php de $folder"; return 1; }
    owner=$(lampp_bd_owner "$from")
    mkdir -p -m 700 "$DOCKER_DIR" "$dir" || return 1
    ( umask 077
      printf 'DB_PASS=%s\n' "$(sed -n 2p <<< "$creds")" > "$dir/.env"
      printf 'MODO=web\nCARPETA=%s\nTIPO=wp\nPHP=%s\nACTIVA=%s\nMARIADB=%s\nBBDD=%s\nUSUARIO=%s\nCONFIG=wp-config.php\nLAMPP_BD=%s\n' \
          "$folder" "$php" "$php" "$maria" "$(head -1 <<< "$creds" | cut -d'|' -f2)" "${creds%%|*}" "$owner" > "$dir/proyecto.conf"
      docker_fpm_conf > "$dir/fpm.conf" ) || return 1
    docker_conf_set "$slug" DOMINIO "$(docker_web_domain "$slug" "$php")"
    docker_web_config "$slug" "$php" && docker_web_compose "$slug" || return 1
    task_plan "Montando $folder en Docker" "Imagen de PHP $php" "BBDD en vivo" "Apache de Docker" "Certificado en el navegador"
    task_step
    echo "1/4 Imagen de PHP $php"
    docker_php_image "$php" || { echo "No se ha podido preparar la imagen de PHP $php"; return 1; }
    task_step
    echo "2/4 BBDD $(docker_conf "$slug" BBDD) de lampp-$owner, en vivo (la misma que web.local)"
    lampp_bd_up "$owner" && lampp_bd_bridge_up "$owner" || return 1
    task_step
    echo "3/4 Apache de Docker y $(docker_web_domain "$slug" "$php")"
    docker_web_hosts poner "$(docker_web_pma)" "$(docker_web_domain "$slug" "$php")" || return 1
    docker_web_up || return 1
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d "php${php//./}" || return 1
    task_step
    echo "4/4 Certificado en el navegador"
    docker_web_trust
    echo "Proyecto en Docker listo: $(docker_web_url "$(docker_web_domain "$slug" "$php")") (PHP $php), con la BBDD de lampp-$owner en vivo"
}

# docker-php-añadir <nombre> <php>: otra version de PHP del mismo proyecto, con la misma carpeta y la
# misma BBDD. En WordPress va a la vez que las demas, con su dominio; en una tienda pasa a ser la elegida
function docker_web_add() {
    local slug=$1 php=$2 dir list
    docker_web_project "$slug" || { echo "No hay ningun proyecto en Docker (con el Apache de Docker) con el nombre $slug"; return 1; }
    [[ " $DOCKER_PHP_VERSIONS " == *" $php "* ]] || { echo "PHP $php no se ofrece en Docker ($DOCKER_PHP_VERSIONS)"; return 1; }
    dir=$DOCKER_DIR/$slug
    list=$(docker_conf "$slug" PHP)
    [[ " $list " == *" $php "* ]] && { echo "$slug ya tiene PHP $php"; return 0; }
    echo "$slug: añade PHP $php (la misma carpeta y la misma BBDD)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] contenedor $(docker_web_container "$slug" "$php") y $(docker_web_url "$(docker_web_domain "$slug" "$php")")"
        return 0
    fi
    docker_ready || { echo "Docker sin root no esta en marcha"; return 1; }
    docker_dns_on || sudo_first || return 1
    docker_php_image "$php" || { echo "No se ha podido preparar la imagen de PHP $php"; return 1; }
    docker_conf_set "$slug" PHP "$(tr ' ' '\n' <<< "$list $php" | sort -t. -k1,1nr -k2,2nr | tr '\n' ' ' | sed 's/ $//')" || return 1
    docker_web_config "$slug" "$php" && docker_web_compose "$slug" || return 1
    if [ "$(docker_conf "$slug" TIPO)" == ps ]; then
        docker_web_switch "$slug" "$php"
        return
    fi
    docker_web_hosts poner "$(docker_web_domain "$slug" "$php")" || return 1
    docker_maria_up "$(docker_conf "$slug" MARIADB)" && docker_web_up || return 1
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d "php${php//./}" || return 1
    echo "Listo: $(docker_web_url "$(docker_web_domain "$slug" "$php")") (PHP $php)"
}

#@incluir comun/docker-su-propio-apache/docker_web_remove.sh
# docker-php-elegir <nombre> <php>: la version de PHP con la que va una tienda PrestaShop (va con un
# solo dominio): se arranca esa, el dominio pasa a ella y se para la de antes
function docker_web_switch() {
    local slug=$1 php=$2 dir old
    docker_web_project "$slug" || { echo "No hay ningun proyecto en Docker (con el Apache de Docker) con el nombre $slug"; return 1; }
    [[ " $(docker_conf "$slug" PHP) " == *" $php "* ]] || { echo "$slug no tiene PHP $php: añadela antes (docker-php-añadir)"; return 1; }
    dir=$DOCKER_DIR/$slug
    old=$(docker_conf "$slug" ACTIVA)
    echo "$slug: $(docker_web_domain "$slug" "$php") pasa a PHP $php"
    [ "$DRY" -eq 1 ] && return 0
    docker_ready || { echo "Docker sin root no esta en marcha"; return 1; }
    docker_conf_set "$slug" ACTIVA "$php" || return 1
    docker_web_hosts poner "$(docker_web_domain "$slug" "$php")" || return 1
    docker_maria_up "$(docker_conf "$slug" MARIADB)" || return 1
    local fresh=()
    docker_fpm_refresh "$slug" && fresh=(--force-recreate)
    if ! dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d "${fresh[@]}" "php${php//./}"; then
        echo "No arranca con PHP $php: sigue con PHP $old"
        docker_conf_set "$slug" ACTIVA "$old"
        return 1
    fi
    docker_web_up || return 1
    if [ -n "$old" ] && [ "$old" != "$php" ]; then
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" rm -sf "php${old//./}" > /dev/null 2>&1
    fi
    echo "Listo: $(docker_web_url "$(docker_web_domain "$slug" "$php")") con PHP $php"
}

# Acciones de un proyecto del sistema nuevo (las de docker_action): arrancar (con su MariaDB y el Apache
# de Docker), parar (sus PHP: lo comun se queda), registros y borrar (sus contenedores, su BBDD y su
# usuario de la MariaDB comun, sus dominios de hosts y su carpeta del gestor; la del proyecto, no)
function docker_web_action() {
    local action=$1 slug=$2 dir=$DOCKER_DIR/$2 maria
    local c=(dk compose --project-directory "$dir" -f "$dir/compose.yaml")
    maria=$(docker_conf "$slug" MARIADB)
    case $action in
        arrancar)
            [ "$DRY" -eq 1 ] && { echo "  [simulacion] MariaDB $maria, Apache de Docker y $(docker_web_services "$slug" | tr '\n' ' ')"; return 0; }
            docker_idle_ensure
            # (su configuracion, al dia: la de su wp-config.php y las direcciones de la web en local)
            if [ -n "$(docker_conf "$slug" CONFIG)" ]; then
                local v
                for v in $(docker_conf "$slug" PHP); do docker_web_config "$slug" "$v" > /dev/null || return 1; done
            fi
            if [ -n "$(docker_conf "$slug" LAMPP_BD)" ]; then
                lampp_bd_up "$(docker_conf "$slug" LAMPP_BD)" && lampp_bd_bridge_up "$(docker_conf "$slug" LAMPP_BD)" || return 1
                docker_web_up || return 1
            else
                docker_maria_up "$maria" && docker_web_up || return 1
            fi
            local fresh=()
            docker_fpm_refresh "$slug" && fresh=(--force-recreate)
            run "${c[@]}" up -d "${fresh[@]}" $(docker_web_services "$slug") ;;
        parar) run "${c[@]}" stop && docker_web_idle_stop && lampp_bd_release "$(docker_conf "$slug" LAMPP_BD)" "$slug" ;;
        registros) "${c[@]}" logs --no-color --tail 200 ;;
        borrar)
            local db user domains
            db=$(docker_conf "$slug" BBDD) user=$(docker_conf "$slug" USUARIO)
            mapfile -t domains < <(docker_web_domains "$slug")
            # (con la BBDD de LAMPP en vivo, la que se borra es su copia de Docker, si tiene: la de LAMPP nunca)
            if [ -n "$(docker_conf "$slug" LAMPP_BD)" ]; then
                db=$(docker_conf "$slug" BBDD_DOCKER) user=$(docker_conf "$slug" USUARIO_DOCKER)
            fi
            echo "Se borran los contenedores de $slug${db:+ y su BBDD $db de la MariaDB $maria de Docker} (la de LAMPP no se toca)"
            [ "$DRY" -eq 1 ] && return 0
            run "${c[@]}" down -v || return 1
            lampp_bd_release "$(docker_conf "$slug" LAMPP_BD)" "$slug"
            if db_valid_name "$db" > /dev/null && [[ "$user" =~ ^[A-Za-z0-9_]{1,32}$ ]] && docker_maria_up "$maria" > /dev/null; then
                printf 'DROP DATABASE IF EXISTS `%s`;\nDROP USER IF EXISTS '"'"'%s'"'"'@'"'"'%%'"'"';\n' "$db" "$user" | docker_maria_sql "$maria"
            fi
            docker_web_hosts quitar "${domains[@]}"
            rm -rf "$dir"
            docker_web_reload
            echo "Proyecto en Docker $slug borrado" ;;
    esac
}

# Lo comun que ya no usa nadie, parado: una MariaDB comun sin ningun PHP en marcha de los proyectos
# que van con ella y, sin ningun PHP del Apache de Docker en marcha, el Apache de Docker y su phpMyAdmin.
# (Nada de Nexum arranca solo: restart "no". Lo comun se queda al parar un proyecto por si lo usa otro)
function docker_web_idle_stop() {
    local up p v name used=() web_used=0
    [ "$DRY" -eq 1 ] && return 0
    up=$(dk ps --format '{{.Names}}' 2> /dev/null) || return 0
    for p in $(docker_web_projects); do
        if grep -qE "^nexum-$p-php[0-9]{2}\$" <<< "$up"; then
            web_used=1
            # (los que van en vivo con la BBDD de LAMPP no usan la MariaDB comun)
            [ -z "$(docker_conf "$p" LAMPP_BD)" ] && used+=("$(docker_conf "$p" MARIADB)")
        fi
    done
    for name in $(grep -E '^nexum-mariadb-[0-9]{1,2}-[0-9]{1,2}$' <<< "$up"); do
        v=${name#nexum-mariadb-} v=${v/-/.}
        if ! printf '%s\n' "${used[@]}" | grep -qxF "$v"; then
            echo "MariaDB $v de Docker: ya no la usa ningun proyecto en marcha, se para"
            run dk stop "$name" > /dev/null
        fi
    done
    if [ "$web_used" -eq 0 ] && grep -qxE 'nexum-(web|pma)' <<< "$up"; then
        echo "Apache de Docker: ya no hay ningun proyecto en marcha con el, se para (y su phpMyAdmin)"
        run dk stop $(grep -xE 'nexum-(web|pma)' <<< "$up") > /dev/null
    fi
    return 0
}

