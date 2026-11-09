# ===========================================================================
# Docker con su propio Apache: un proyecto en varias versiones de PHP a la vez, sin XAMPP-X
# ===========================================================================
# Desde la 1.40 (Mac) los proyectos nuevos en Docker no pasan por el Apache de XAMPP-X: Docker Desktop tiene
# el suyo (nexum-web, la imagen oficial de Apache) en otra direccion de este Mac (127.0.0.2 por defecto:
# DOCKER_WEB_FILE), asi que funcionan con XAMPP-X parado o con cualquier version activa. macOS solo tiene
# 127.0.0.1: la otra se da de alta una vez (docker-web permitir, con un servicio del sistema que la pone
# en cada arranque: DOCKER_LOOPBACK_PLIST). El Apache de Docker lleva la barrera entre webs y pasa cada
# dominio al contenedor de su version de PHP (nexum-<proyecto>-php83: la imagen nexum-php de siempre,
# Apache con PHP, con los .htaccess y las reglas de los ficheros que no se sirven) por la red interna de
# Docker (nexum), sin puertos abiertos fuera y con la clave del proyecto (X-Nexum-Key). Las BBDD van en
# una MariaDB comun por version de MariaDB (nexum-mariadb-11-8), cada proyecto con su BBDD y su usuario,
# y hay un solo phpMyAdmin (https://pma.docker.local, con su pantalla de acceso). Un proyecto puede tener
# varias versiones de PHP a la vez con la misma BBDD: en WordPress, cada una con su dominio
# (<proyecto>-php83.docker.local, su wp-config.php del contenedor lo lleva); una tienda PrestaShop guarda
# su dominio en la BBDD, asi que va con uno solo (<proyecto>.docker.local) y la version que se elija. Un
# certificado propio para *.docker.local, que no es de una CA: no vale para ninguna otra web. Los
# proyectos de antes (con XAMPP-X delante) siguen igual hasta que se pasan (docker-pasar)
# (httpd fijado por su huella: la etiqueta 2.4 la puede mover cualquiera que llegue a esa cuenta de
# Docker Hub. Es la 2.4.69, Debian trixie, del 21/10/2026; para otra: docker buildx imagetools inspect)
DOCKER_WEB_IMAGE="httpd:2.4.69@sha256:a30cd4cd57f3f3c3be9b2d16384d2488839996bb14c67df2b51f1ecbb3e584a1"
DOCKER_WEB_DIR=$DOCKER_DIR/web
DOCKER_WEB_FILE="$DOCKER_DIR/web.conf"
# Servicio del sistema que da de alta la direccion del Apache de Docker en lo0 en cada arranque
DOCKER_LOOPBACK_PLIST=${LVM_LOOPBACK_PLIST:-/Library/LaunchDaemons/dev.hexer.nexum-direccion.plist}

# Direccion (IP) y puertos (HTTP, HTTPS) del Apache de Docker. Siempre de 127.x: nunca abiertos a la red
function docker_web_get() {
    local v def
    case $1 in IP) def=127.0.0.2 ;; HTTP) def=80 ;; HTTPS) def=443 ;; TLD) def=docker.local ;; DNS) def=0 ;; *) return 1 ;; esac
    v=$(awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$DOCKER_WEB_FILE" 2> /dev/null)
    case $1 in
        IP) docker_web_valid_ip "$v" || v=$def ;;
        TLD) [ "$v" == docker.test ] || v=$def ;;
        DNS) [ "$v" == 1 ] || v=$def ;;
        *) [[ "$v" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$v" -le 65535 ] || v=$def ;;
    esac
    echo "$v"
}

# Guarda web.conf (solo tuyo): docker_web_conf_write <ip> <http> <https> <tld> <dns>
function docker_web_conf_write() {
    mkdir -p -m 700 "$DOCKER_DIR" || return 1
    ( umask 077; printf 'IP=%s\nHTTP=%s\nHTTPS=%s\nTLD=%s\nDNS=%s\n' "$@" > "$DOCKER_WEB_FILE.nuevo" ) \
        && mv -f "$DOCKER_WEB_FILE.nuevo" "$DOCKER_WEB_FILE"
}

# Final de los dominios del Apache de Docker: docker.local (en /etc/hosts, uno a uno) o, con el DNS
# comodin, docker.test. .local es de mDNS: un DNS para *.docker.local no se consultaria
function docker_web_tld() {
    docker_web_get TLD
}

# ¿Va el DNS comodin de *.docker.test? (sus dominios ya no van en /etc/hosts)
function docker_dns_on() {
    [ "$(docker_web_get DNS)" == 1 ] && [ "$(docker_web_get TLD)" == docker.test ]
}

# Dominio de phpMyAdmin
function docker_web_pma() {
    echo "pma.$(docker_web_tld)"
}

function docker_web_valid_ip() {
    [[ "$1" =~ ^127\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] \
        && [ "${BASH_REMATCH[1]}" -le 255 ] && [ "${BASH_REMATCH[2]}" -le 255 ] && [ "${BASH_REMATCH[3]}" -le 254 ] \
        && [ "${BASH_REMATCH[3]}" -ge 1 ]
}

# Direccion de una web del Apache de Docker: https://<dominio>, con el puerto si no es el 443
function docker_web_url() {
    local port=$(docker_web_get HTTPS)
    echo "https://$1$([ "$port" == 443 ] || echo ":$port")"
}

# ¿Esta la direccion del Apache de Docker en este Mac? (127.0.0.1 siempre; otra, si se ha dado de alta en
# lo0). Docker Desktop abre los puertos de menos de 1024 sin pedir nada mas
function docker_web_ports_ok() {
    local ip
    ip=$(docker_web_get IP)
    [ "$ip" == 127.0.0.1 ] && return 0
    if [ -n "$LVM_LO0_FILE" ]; then
        grep -qx "$ip" "$LVM_LO0_FILE" 2> /dev/null
        return
    fi
    /sbin/ifconfig lo0 2> /dev/null | grep -q "inet ${ip//./\\.} "
}

# Nombres de lo comun: la MariaDB de una version (nexum-mariadb-11-8) y el contenedor de PHP de una
# version de un proyecto (nexum-<proyecto>-php83)
function docker_maria_name() {
    echo "nexum-mariadb-${1//./-}"
}
function docker_web_container() {
    echo "nexum-$1-php${2//./}"
}

# ¿Es un proyecto del sistema nuevo (con el Apache de Docker)?
function docker_web_project() {
    docker_valid_slug "$1" && [ "$(docker_conf "$1" MODO)" == web ]
}

# Dominio de una version de PHP de un proyecto: el de la tienda (uno solo) o <proyecto>-php83.docker.local
function docker_web_domain() {
    if [ "$(docker_conf "$1" TIPO)" == ps ]; then
        echo "$1.$(docker_web_tld)"
    else
        echo "$1-php${2//./}.$(docker_web_tld)"
    fi
}

# Dominios de un proyecto (todas sus versiones)
function docker_web_domains() {
    local v
    for v in $(docker_conf "$1" PHP); do docker_web_domain "$1" "$v"; done | awk '!seen[$0]++'
}

# Proyectos del sistema nuevo
function docker_web_projects() {
    local p
    for p in $(docker_projects); do
        [ "$(docker_conf "$p" MODO)" == web ] && echo "$p"
    done
}

# La red interna de Docker que comparten el Apache, las MariaDB y los PHP (sin puertos fuera)
function docker_net() {
    dk network inspect nexum > /dev/null 2>&1 || dk network create nexum > /dev/null
}

# SQL como root en la MariaDB comun de una version: docker_maria_sql <version> [argumentos de mariadb].
# La contraseña no va en ninguna orden (se ve en ps): el cliente la toma dentro del contenedor
function docker_maria_sql() {
    local v=$1
    shift
    dk exec -i "$(docker_maria_name "$v")" \
        sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot "$@"' mariadb "$@"
}

# La MariaDB comun de una version: la crea (su compose.yaml y su contraseña de root al azar, en
# ficheros solo tuyos) si no existe, la arranca y espera a que responda
function docker_maria_up() {
    local v=$1 name dir i
    [[ " $DOCKER_MARIADB_VERSIONS " == *" $v "* ]] || { echo "MariaDB $v no se ofrece en Docker ($DOCKER_MARIADB_VERSIONS)"; return 1; }
    name=$(docker_maria_name "$v") dir=$DOCKER_DIR/mariadb-$v
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] MariaDB $v comun ($name) en marcha"
        return 0
    fi
    if [ ! -f "$dir/compose.yaml" ]; then
        mkdir -p -m 700 "$DOCKER_DIR" "$dir" || return 1
        ( umask 077
          printf 'DB_ROOT_PASS=%s\n' "$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')" > "$dir/.env"
          { printf 'name: %s\nservices:\n  db:\n    image: mariadb:%s\n    container_name: %s\n    restart: "no"\n' "$name" "$v" "$name"
            printf '    environment:\n      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASS}\n      MARIADB_AUTO_UPGRADE: "1"\n'
            printf '    command: ["--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci", "--max-allowed-packet=512M"]\n'
            printf '    volumes:\n      - "datos:/var/lib/mysql"\n    networks: [nexum]\n'
            printf 'volumes:\n  datos:\n    name: %s\n' "$name"
            printf 'networks:\n  nexum:\n    external: true\n    name: nexum\n'; } > "$dir/compose.yaml" ) || return 1
    fi
    docker_net || return 1
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d || return 1
    for i in $(seq 90); do
        docker_maria_sql "$v" -e "SELECT 1" < /dev/null > /dev/null 2>&1 && return 0
        sleep 1
    done
    echo "La MariaDB $v de Docker no responde (mira sus registros en la pestaña Docker)"
    return 1
}

# MariaDB comunes que hay (sus versiones)
function docker_maria_versions() {
    local d
    for d in "$DOCKER_DIR"/mariadb-*/; do
        d=$(basename "$d")
        d=${d#mariadb-}
        [[ " $DOCKER_MARIADB_VERSIONS " == *" $d "* ]] && [ -f "$DOCKER_DIR/mariadb-$d/compose.yaml" ] && echo "$d"
    done
}

# Certificado propio de *.docker.local (no es de una CA: solo vale para esos dominios), en una carpeta
# solo tuya que Docker Desktop comparte con el Apache de Docker (825 dias: lo maximo que acepta Safari)
function docker_web_cert() {
    local c=$DOCKER_WEB_DIR/certs tmp
    if [ -s "$c/docker.local.crt" ] && [ -s "$c/docker.local.key" ]; then
        openssl x509 -in "$c/docker.local.crt" -noout -text 2> /dev/null | grep -q 'DNS:\*\.docker\.test' && return 0
        [ "$DRY" -eq 1 ] || rm -f "$c/docker.local.crt" "$c/docker.local.key"
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] certificado propio de *.docker.local en $c"
        return 0
    fi
    mkdir -p -m 700 "$DOCKER_DIR" "$DOCKER_WEB_DIR" "$c" || return 1
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-cert.XXXXXX") || return 1
    # (las extensiones en un fichero de configuracion: la LibreSSL de macOS 12 no tiene -addext)
    printf '[req]\ndistinguished_name = dn\nx509_extensions = ext\nprompt = no\n[dn]\nCN = docker.local\n[ext]\nbasicConstraints = critical,CA:FALSE\nextendedKeyUsage = serverAuth\nsubjectAltName = DNS:docker.local,DNS:*.docker.local,DNS:docker.test,DNS:*.docker.test\n' > "$tmp/cnf"
    if ! ( umask 077; openssl req -x509 -nodes -newkey rsa:2048 -days 825 -config "$tmp/cnf" \
            -keyout "$c/docker.local.key" -out "$c/docker.local.crt" > /dev/null 2>&1 ); then
        rm -rf "$tmp"
        rm -f "$c/docker.local.key" "$c/docker.local.crt"
        echo "No se ha podido crear el certificado de *.docker.local"
        return 1
    fi
    rm -rf "$tmp"
    echo "Certificado propio de *.docker.local y *.docker.test (solo vale para esos dominios)"
}

# Safari y Chrome aceptan sin aviso el certificado de *.docker.local: va a tus ajustes de confianza del
# llavero (como los de las tiendas falseadas), solo para servidores (ssl)
function docker_web_trust() {
    local crt=$DOCKER_WEB_DIR/certs/docker.local.crt
    # (en las pruebas, nunca en el llavero de verdad)
    [ -n "$TEST_DIR" ] && return 0
    [ -f "$crt" ] || [ "$DRY" -eq 1 ] || return 0
    if [ "$DRY" -eq 0 ] && security verify-cert -c "$crt" -p ssl -s pma.docker.local > /dev/null 2>&1; then
        echo "El navegador ya acepta el certificado de *.docker.local"
        return 0
    fi
    echo "El Mac te pide la contraseña para que el navegador acepte el certificado de *.docker.local..."
    if ! run security add-trusted-cert -r trustRoot -p ssl -k "$HOME/Library/Keychains/login.keychain-db" "$crt"; then
        echo "No se ha cambiado (¿has cancelado la contraseña?): pulsa «Confiar» en Configuracion, Docker"
        return 0
    fi
    echo "El navegador acepta el certificado de *.docker.local (Safari, Chrome; Firefox, si usa los certificados del Mac)"
}

# Lineas de /etc/hosts de los dominios de Docker: docker_web_hosts poner|quitar <dominio...>. poner: a la
# direccion del Apache de Docker (y fuera de cualquier otra linea); quitar: fuera. Solo esos dominios
function docker_web_hosts() {
    local mode=$1 copy rc n names=()
    shift
    # (con el DNS comodin, los *.docker.test los contesta el; solo se tocan los de antes)
    for n in "$@"; do
        docker_dns_on && [[ "$n" == *.docker.test ]] && continue
        names+=("$n")
    done
    set -- "${names[@]}"
    [ $# -gt 0 ] || return 0
    mkdir -p -m 700 "$LOG_DIR" || return 1
    copy=$(mktemp "$LOG_DIR/hosts-docker-XXXXXX") || return 1
    python3 -I - "$HOSTS_FILE" "$copy" "$mode" "$(docker_web_get IP)" "$@" << 'EOF'
import re, sys
src, dst, mode, ip = sys.argv[1:5]
names = [n.lower() for n in sys.argv[5:]]
lines = open(src).read().splitlines()
now = {}
for line in lines:
    w = line.split("#", 1)[0].split()
    for n in w[1:]:
        now.setdefault(n.lower(), w[0])
if mode == "poner" and all(now.get(n) == ip for n in names):
    out = lines
else:
    out = []
    for line in lines:
        body, sep, comment = line.partition("#")
        w = body.split()
        if len(w) >= 2 and re.match(r"^(127\.\d+\.\d+\.\d+|::1)$", w[0]):
            keep = [n for n in w[1:] if n.lower() not in names]
            if len(keep) != len(w) - 1:
                if not keep:
                    continue
                line = w[0] + " " + " ".join(keep) + (" " + sep + comment if sep else "")
        out.append(line)
    if mode == "poner":
        out.append(ip + " " + " ".join(names))
open(dst, "w").write("\n".join(out) + "\n")
EOF
    if cmp -s "$copy" "$HOSTS_FILE"; then
        rm -f "$copy"
        return 0
    fi
    edit_hosts --aplicar "$copy"
    rc=$?
    rm -f "$copy"
    return $rc
}

# Reglas de seguridad de todas las webs, las mismas que en XAMPP-X (de UNKNOWN_HOST_VHOST: CORS y la
# barrera entre webs, si esta encendida; las de los ficheros que no se sirven van tambien dentro de cada
# contenedor de PHP, que es el que tiene los ficheros)
function docker_web_security() {
    local text
    text=$(unknown_host_vhost)
    printf '# Configuracion, repositorios%s\n' "${text#*$'\n'# Configuracion, repositorios}"
}

# Vhosts de un proyecto en el Apache de Docker: http lleva a https, y en https todo va al contenedor de su
# version de PHP con su dominio y la clave del proyecto (la configuracion es solo tuya). Una tienda, solo
# la version elegida (ACTIVA)
function docker_web_site() {
    local slug=$1 folder versions v dom key
    folder=$(docker_conf "$slug" CARPETA)
    versions=$(docker_conf "$slug" PHP)
    [ "$(docker_conf "$slug" TIPO)" == ps ] && versions=$(docker_conf "$slug" ACTIVA)
    key=$(sed -n 's/^WEB_KEY=//p' "$DOCKER_DIR/$slug/.env")
    [[ "$key" =~ ^[A-Za-z0-9]{20,}$ ]] || return 1
    printf '# %s (%s)\n' "$slug" "$folder"
    for v in $versions; do
        dom=$(docker_web_domain "$slug" "$v")
        printf '<VirtualHost *:80>\n    ServerName %s\n    Redirect permanent / %s/\n</VirtualHost>\n' "$dom" "$(docker_web_url "$dom")"
        printf '<VirtualHost *:443>\n    ServerName %s\n' "$dom"
        printf '    SSLEngine on\n    SSLCertificateFile /certs/docker.local.crt\n    SSLCertificateKeyFile /certs/docker.local.key\n'
        # (con su PHP parado, por ejemplo al llevar horas sin visitas, lo dice en vez de un error sin mas.
        # Solo los errores del propio Apache: un 503 de la web, como el modo mantenimiento, pasa igual)
        printf '    ErrorDocument 502 "%s"\n    ErrorDocument 503 "%s"\n' "$DOCKER_STOPPED_MSG" "$DOCKER_STOPPED_MSG"
        # (antes que ProxyPass: mod_rewrite va primero)
        [ "$(docker_conf "$slug" TIPO)" == ps ] || docker_web_media "$folder"
        printf '    ProxyPreserveHost On\n    ProxyPass / http://%s/\n    ProxyPassReverse / http://%s/\n' \
            "$(docker_web_container "$slug" "$v")" "$(docker_web_container "$slug" "$v")"
        printf '    RequestHeader set X-Forwarded-Proto "https"\n    RequestHeader set X-Nexum-Key "%s"\n' "$key"
        printf '</VirtualHost>\n'
    done
}

# Reglas de las imagenes de produccion de un WordPress en el Apache de Docker (su dominio, el de media-proyecto,
# el mismo que con LAMPP): lo que falte de wp-content/uploads (imagenes, videos y PDF; solo GET y HEAD) se pide
# a su web real con una redireccion 302. Nada si no tiene dominio de produccion
function docker_web_media() {
    local folder=$1 prod
    prod=$(media_saved "$folder")
    valid_domain "$prod" && [[ "$prod" != *.local && "$prod" != *.test && "$prod" != localhost && "$prod" != *.localhost ]] || return 0
    printf '    # nexum-media %s: lo que falte de wp-content/uploads se pide a produccion (media-proyecto)\n' "$prod"
    printf '    RewriteEngine On\n    RewriteCond %%{REQUEST_METHOD} ^(GET|HEAD)$\n'
    printf '    RewriteCond /opt/lampp/htdocs/%s%%{REQUEST_URI} !-f\n' "$folder"
    printf '    RewriteRule ^/(wp-content/uploads/.+\\.(%s))$ https://%s/$1 [NC,R=302,L]\n' "$MEDIA_EXT" "$prod"
}

# Configuracion del Apache de Docker (httpd.conf, las reglas, un vhost por proyecto y el de phpMyAdmin,
# en DOCKER_WEB_DIR/conf) y su compose.yaml. Se escribe entera cada vez (lo sabe todo de proyecto.conf).
# La carpeta conf va montada en el contenedor: se cambia lo de dentro, nunca la carpeta (el contenedor
# seguiria viendo la de antes)
DOCKER_WEB_CONF=/usr/local/apache2/conf/nexum/httpd.conf
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
# (los procesos que sirven las webs, con un usuario sin privilegios del contenedor)
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
      printf '    volumes:\n      - "%s:/opt/lampp/htdocs:ro"\n      - "./conf:/usr/local/apache2/conf/nexum:ro"\n      - "./certs:/certs:ro"\n' "$HTDOCS_DIR"
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
        echo "La direccion $(docker_web_get IP) aun no esta en este Mac."
        echo "Pulsa «Permitir» en Configuracion, Docker (o: lvm-instalador docker-web permitir), o elige otra direccion."
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

# Vuelve a escribir la configuracion del Apache de Docker y, si esta en marcha, la recarga sin cortar las
# conexiones (si Apache no la acepta, lo dice y sigue con la de antes)
function docker_web_reload() {
    local out
    [ "$DRY" -eq 1 ] && return 0
    [ "$1" == --sin-escribir ] || docker_web_write || return 1
    [ "$(docker_web_state)" == marcha ] || return 0
    if ! out=$(dk exec nexum-web httpd -f "$DOCKER_WEB_CONF" -t 2>&1); then
        echo "El Apache de Docker no acepta su configuracion nueva: sigue con la de antes"
        sed 's/^/  /' <<< "$out" | tail -5
        return 1
    fi
    dk exec nexum-web httpd -f "$DOCKER_WEB_CONF" -k graceful > /dev/null 2>&1
}

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
            docker_ready || { echo "Docker Desktop no esta en marcha"; return 1; }
            docker_web_up ;;
        parar)
            [ "$DRY" -eq 1 ] && { echo "  [simulacion] Apache de Docker y phpMyAdmin parados"; return 0; }
            run dk compose --project-directory "$DOCKER_WEB_DIR" -f "$DOCKER_WEB_DIR/compose.yaml" stop ;;
        confiar) docker_web_trust ;;
        *) echo "Uso: lvm-instalador docker-web [estado] | puertos <ip> <http> <https> | permitir | arrancar | parar | confiar | dns activar|quitar"; return 1 ;;
    esac
}

# docker-web puertos <ip> <http> <https>: otra direccion (siempre de 127.x) u otros puertos. Con los de
# siempre (80 y 443) no puede ser 127.0.0.1: los usa el Apache de XAMPP-X. Los dominios de Docker pasan
# a la direccion nueva en /etc/hosts y el Apache de Docker se vuelve a crear (una direccion nueva se da
# de alta con «Permitir»)
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
        echo "En 127.0.0.1 los puertos 80 y 443 son del Apache de XAMPP-X: usa otra direccion (127.0.0.2) u otros puertos"
        return 1
    fi
    echo "Apache de Docker: $ip, puertos $http (http) y $https (https)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] se guarda en $DOCKER_WEB_FILE y los dominios de Docker pasan a $ip en $HOSTS_FILE"
        return 0
    fi
    mkdir -p -m 700 "$DOCKER_DIR" || return 1
    docker_web_conf_write "$ip" "$http" "$https" "$(docker_web_tld)" "$(docker_web_get DNS)" || return 1
    docker_web_ports_ok || echo "Aviso: $ip aun no esta en este Mac: pulsa «Permitir» (lvm-instalador docker-web permitir)"
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

# docker-web permitir: la direccion del Apache de Docker (127.0.0.2) en este Mac. macOS solo tiene
# 127.0.0.1: se da de alta en lo0 y un servicio del sistema (de root) la vuelve a poner en cada
# arranque. Solo es de este Mac (lo0): nunca abierta a la red. Pide la contraseña de administrador
function docker_web_allow() {
    local ip tmp
    ip=$(docker_web_get IP)
    if docker_web_ports_ok; then
        echo "La direccion $ip ya esta en este Mac"
        return 0
    fi
    echo "Se da de alta $ip en este Mac (lo0) y se deja puesta en cada arranque ($DOCKER_LOOPBACK_PLIST)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] sudo ifconfig lo0 alias $ip up y el servicio $DOCKER_LOOPBACK_PLIST"
        return 0
    fi
    sudo_first || return 1
    tmp=$(mktemp "${TMPDIR:-/tmp}/lvm-direccion.XXXXXX") || return 1
    cat > "$tmp" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.hexer.nexum-direccion</string>
    <key>ProgramArguments</key>
    <array>
        <string>/sbin/ifconfig</string>
        <string>lo0</string>
        <string>alias</string>
        <string>$ip</string>
        <string>up</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
    # (de root y solo lo puede cambiar root: launchd lo ejecuta como root en cada arranque)
    $SUDO launchctl bootout system "$DOCKER_LOOPBACK_PLIST" > /dev/null 2>&1
    $SUDO install -o 0 -g 0 -m 644 "$tmp" "$DOCKER_LOOPBACK_PLIST" && rm -f "$tmp" || { rm -f "$tmp"; return 1; }
    $SUDO launchctl bootstrap system "$DOCKER_LOOPBACK_PLIST" > /dev/null 2>&1
    $SUDO /sbin/ifconfig lo0 alias "$ip" up || return 1
    docker_web_ports_ok || { echo "No se ha podido dar de alta $ip"; return 1; }
    echo "Listo: $ip ya esta en este Mac (y lo estara en cada arranque)"
}

# El DNS en el Mac: un servicio del sistema (launchd) con el usuario nobody y /etc/resolver/docker.test, con
# el que macOS le pregunta solo lo de docker.test. Todo de root. Con el python3 de las herramientas de
# Xcode (el de /usr/bin solo lo lanza, y como nobody no siempre puede)
DOCKER_DNS_SCRIPT=${LVM_DNS_SCRIPT:-/Library/Nexum/nexum-dns.py}
DOCKER_DNS_PLIST=${LVM_DNS_PLIST:-/Library/LaunchDaemons/dev.hexer.nexum-dns.plist}
DOCKER_DNS_RESOLVER=${LVM_DNS_RESOLVER:-/etc/resolver/docker.test}
function docker_dns_install() {
    local ip py tmp d
    ip=$(docker_web_get IP)
    [ "$DRY" -eq 1 ] && return 0
    py=$(xcrun -f python3 2> /dev/null)
    [ -x "$py" ] || py=/usr/bin/python3
    for d in "$(dirname "$DOCKER_DNS_SCRIPT")" "$(dirname "$DOCKER_DNS_RESOLVER")"; do
        $SUDO mkdir -p "$d" || return 1
    done
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-dns.XXXXXX") || return 1
    printf '%s\n' "$DOCKER_DNS_PY" > "$tmp/nexum-dns.py"
    cat > "$tmp/plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.hexer.nexum-dns</string>
    <key>ProgramArguments</key>
    <array>
        <string>$py</string>
        <string>-I</string>
        <string>$DOCKER_DNS_SCRIPT</string>
        <string>127.0.0.1</string>
        <string>$DOCKER_DNS_PORT</string>
        <string>docker.test</string>
        <string>$ip</string>
    </array>
    <key>UserName</key>
    <string>nobody</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST
    printf 'nameserver 127.0.0.1\nport %s\n' "$DOCKER_DNS_PORT" > "$tmp/resolver"
    $SUDO launchctl bootout system "$DOCKER_DNS_PLIST" > /dev/null 2>&1
    if ! { $SUDO install -o 0 -g 0 -m 644 "$tmp/nexum-dns.py" "$DOCKER_DNS_SCRIPT" \
            && $SUDO install -o 0 -g 0 -m 644 "$tmp/plist" "$DOCKER_DNS_PLIST" \
            && $SUDO install -o 0 -g 0 -m 644 "$tmp/resolver" "$DOCKER_DNS_RESOLVER"; }; then
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    $SUDO launchctl bootstrap system "$DOCKER_DNS_PLIST" || return 1
    $SUDO dscacheutil -flushcache 2> /dev/null
    $SUDO killall -HUP mDNSResponder 2> /dev/null
    return 0
}

function docker_dns_uninstall() {
    [ "$DRY" -eq 1 ] && return 0
    $SUDO launchctl bootout system "$DOCKER_DNS_PLIST" > /dev/null 2>&1
    $SUDO rm -f "$DOCKER_DNS_PLIST" "$DOCKER_DNS_RESOLVER" "$DOCKER_DNS_SCRIPT"
    $SUDO dscacheutil -flushcache 2> /dev/null
    $SUDO killall -HUP mDNSResponder 2> /dev/null
    return 0
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

# ¿Contesta el DNS comodin? (como lo buscan los navegadores: con el sistema)
function docker_dns_works() {
    local ip got i
    ip=$(docker_web_get IP)
    for i in $(seq 20); do
        got=$(python3 -I -c 'import socket, sys
try:
    print(socket.getaddrinfo(sys.argv[1], None, socket.AF_INET)[0][4][0])
except OSError:
    pass' "nexum-comprobacion.docker.test" 2> /dev/null)
        [ "$got" == "$ip" ] && return 0
        sleep 0.5
    done
    return 1
}

# docker_web_retld: los proyectos del Apache de Docker con el final de los dominios de ahora (docker_web_tld):
# su dominio, su configuracion de cada version (WordPress: WP_HOME), el dominio de una tienda en su BBDD y
# sus contenedores de PHP en marcha, rehechos (su configuracion va montada fichero a fichero)
function docker_web_retld() {
    local p state
    for p in $(docker_web_projects); do
        docker_conf_set "$p" DOMINIO "$(docker_web_domain "$p" "$(docker_conf "$p" ACTIVA)")" || return 1
        for v in $(docker_conf "$p" PHP); do
            docker_web_config "$p" "$v" || return 1
        done
        docker_web_compose "$p" || return 1
        if docker_ready; then
            if [ "$(docker_conf "$p" TIPO)" == ps ] && docker_maria_up "$(docker_conf "$p" MARIADB)" > /dev/null; then
                docker_web_ps_domain "$p"
            fi
            state=$(docker_state "$p")
            if [ "$state" == marcha ] || [ "$state" == parcial ]; then
                dk compose --project-directory "$DOCKER_DIR/$p" -f "$DOCKER_DIR/$p/compose.yaml" up -d --force-recreate \
                    $(docker_web_services "$p") > /dev/null || return 1
            fi
        fi
        echo "  $(docker_conf "$p" CARPETA): $(docker_web_url "$(docker_web_domain "$p" "$(docker_conf "$p" ACTIVA)")")"
    done
}

# docker-web dns activar: pone el DNS comodin y pasa los proyectos del Apache de Docker a *.docker.test
# (sus lineas de /etc/hosts se quitan). Si no contesta, se quita y todo sigue como estaba. Pide la
# contraseña de administrador una vez
function docker_dns_activate() {
    local old p olds=()
    if docker_dns_on && docker_dns_works; then
        echo "El DNS de *.docker.test ya va: los dominios de Docker no van en /etc/hosts"
        return 0
    fi
    echo "DNS de *.docker.test: los dominios de Docker pasan a .docker.test y dejan de ir en /etc/hosts"
    echo "(web.local, los proyectos de siempre y los dominios falseados de las tiendas siguen igual)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] DNS en 127.0.0.1:$DOCKER_DNS_PORT para *.docker.test y los proyectos de Docker a .docker.test"
        return 0
    fi
    sudo_first || return 1
    docker_dns_install || { echo "No se ha podido poner el DNS de *.docker.test"; docker_dns_uninstall; return 1; }
    if ! docker_dns_works; then
        echo "El DNS de *.docker.test no contesta: se quita y todo sigue como estaba"
        docker_dns_uninstall
        return 1
    fi
    old=$(docker_web_tld)
    if [ "$old" != docker.test ]; then
        olds+=("pma.$old")
        for p in $(docker_web_projects); do
            mapfile -t -O "${#olds[@]}" olds < <(docker_web_domains "$p")
        done
    fi
    docker_web_conf_write "$(docker_web_get IP)" "$(docker_web_get HTTP)" "$(docker_web_get HTTPS)" docker.test 1 || return 1
    if [ "$old" != docker.test ] && [ -n "$(docker_web_projects)" ]; then
        echo "Los proyectos del Apache de Docker pasan a .docker.test:"
        docker_web_retld || return 1
    fi
    [ ${#olds[@]} -gt 0 ] && docker_web_hosts quitar "${olds[@]}"
    if [ -d "$DOCKER_WEB_DIR" ]; then
        docker_web_cert && docker_web_trust
        if docker_ready && [ "$(docker_web_state)" != nuevo ]; then
            docker_web_up || return 1
        else
            docker_web_write
        fi
    fi
    echo "Listo: los proyectos de Docker se abren en $(docker_web_url "<proyecto>.docker.test") y phpMyAdmin en $(docker_web_url "$(docker_web_pma)")"
}

# docker-web dns quitar: sin el DNS comodin. Los dominios siguen siendo .docker.test y vuelven a /etc/hosts
function docker_dns_deactivate() {
    local p domains=()
    echo "Se quita el DNS de *.docker.test: sus dominios vuelven a /etc/hosts"
    [ "$DRY" -eq 1 ] && return 0
    sudo_first || return 1
    docker_web_conf_write "$(docker_web_get IP)" "$(docker_web_get HTTP)" "$(docker_web_get HTTPS)" "$(docker_web_tld)" 0 || return 1
    docker_dns_uninstall
    for p in $(docker_web_projects); do
        mapfile -t -O "${#domains[@]}" domains < <(docker_web_domains "$p")
    done
    [ -d "$DOCKER_WEB_DIR" ] && { docker_web_hosts poner "$(docker_web_pma)" "${domains[@]}" || return 1; }
    echo "Listo: los dominios de Docker van otra vez en /etc/hosts"
}

function docker_dns_command() {
    case $1 in
        activar) docker_dns_activate ;;
        quitar) docker_dns_deactivate ;;
        *) echo "Uso: lvm-instalador docker-web dns activar|quitar"; return 1 ;;
    esac
}

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
    # (la BBDD: la de una version XAMPP-X en vivo, por su puente, o la de la MariaDB comun)
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
# version (Apache con PHP, que solo responde con la clave del proyecto y su dominio), la carpeta en la
# misma ruta que en el Mac, su configuracion de solo lectura encima de la del proyecto y, en PrestaShop
# 1.7 o posterior, su cache en un volumen propio de cada version
function docker_web_compose() {
    local slug=$1 dir=$DOCKER_DIR/$1 folder rel v vv vols="" root
    folder=$(docker_conf "$slug" CARPETA) rel=$(docker_conf "$slug" CONFIG)
    root=$LINK/xamppfiles/htdocs/$folder
    docker_prefork_conf | cmp -s - "$DOCKER_PREFORK_CONF" || ( umask 077; docker_prefork_conf > "$DOCKER_PREFORK_CONF" ) || return 1
    { printf 'name: nexum-%s\nservices:\n' "$slug"
      for v in $(docker_conf "$slug" PHP); do
          vv=${v//./}
          printf '  php%s:\n    image: nexum-php:%s\n    container_name: %s\n    restart: "no"\n' "$vv" "$v" "$(docker_web_container "$slug" "$v")"
          printf '    environment:\n      NEXUM_KEY: ${WEB_KEY}\n      NEXUM_DOMAIN: "%s"\n      NEXUM_ROOT: "%s"\n' "$(docker_web_domain "$slug" "$v")" "$root"
          printf '    volumes:\n      - "%s:%s"\n' "$HTDOCS_DIR/$folder" "$root"
          printf '      - "%s:/etc/apache2/mods-available/mpm_prefork.conf:ro"\n' "$DOCKER_PREFORK_CONF"
          [ -n "$rel" ] && [ -f "$dir/config-$vv.php" ] && printf '      - "./config-%s.php:%s/%s:ro"\n' "$vv" "$root" "$rel"
          if [ "$rel" == app/config/parameters.php ]; then
              printf '      - "cache-%s:%s/var/cache"\n' "$vv" "$root"
              vols+="  cache-$vv: {}"$'\n'
          fi
          printf '    networks: [nexum]\n'
      done
      [ -n "$vols" ] && printf 'volumes:\n%s' "$vols"
      printf 'networks:\n  nexum:\n    external: true\n    name: nexum\n'; } > "$dir/compose.yaml.nuevo" \
        && mv -f "$dir/compose.yaml.nuevo" "$dir/compose.yaml"
}

# Procesos del Apache con PHP de los contenedores (prefork, de todos los proyectos): uno esperando y, sin
# trabajo, no mas de dos (de fabrica, cinco esperando: 100-250 MB por contenedor). Cada uno se
# rehace a las 200 peticiones (PHP no le crece). Va en DOCKER_DIR/apache-ligero.conf y en cada contenedor
# en lugar del de la imagen. Lo escribe docker_web_compose
DOCKER_PREFORK_CONF=$DOCKER_DIR/apache-ligero.conf
function docker_prefork_conf() {
    printf '# Nexum Dev Stack: pocos procesos esperando (se rehace solo)\n<IfModule mpm_prefork_module>\n    StartServers 1\n    MinSpareServers 1\n    MaxSpareServers 2\n    MaxRequestWorkers 20\n    MaxConnectionsPerChild 200\n</IfModule>\n'
}

# Servicios que van en marcha: todas las versiones o, en una tienda, la elegida
function docker_web_services() {
    local v
    if [ "$(docker_conf "$1" TIPO)" == ps ]; then
        v=$(docker_conf "$1" ACTIVA)
        echo "php${v//./}"
    else
        for v in $(docker_conf "$1" PHP); do echo "php${v//./}"; done
    fi
}

# Cambia una clave de proyecto.conf
function docker_conf_set() {
    local f=$DOCKER_DIR/$1/proyecto.conf
    [ -f "$f" ] && [ ! -L "$f" ] || return 1
    awk -F= -v k="$2" -v v="$3" 'BEGIN { done = 0 } $1 == k { print k "=" v; done = 1; next } { print } END { if (!done) print k "=" v }' \
        "$f" > "$f.nuevo" && chmod 600 "$f.nuevo" && mv -f "$f.nuevo" "$f"
}

# Tienda PrestaShop en la MariaDB comun: su dominio pasa a ser el de Docker (la BBDD es una copia)
function docker_web_ps_domain() {
    local slug=$1 v db dom prefix
    v=$(docker_conf "$slug" MARIADB) db=$(docker_conf "$slug" BBDD)
    dom=$(docker_web_domain "$slug" "")
    [ "$(docker_web_get HTTPS)" == 443 ] || dom+=":$(docker_web_get HTTPS)"
    prefix=$(docker_maria_sql "$v" -N -e "SELECT LEFT(table_name, LENGTH(table_name) - 8) FROM information_schema.tables
        WHERE table_schema = '$db' AND table_name LIKE '%shop\\_url' AND table_type = 'BASE TABLE' LIMIT 1" < /dev/null 2> /dev/null | tr -d '\r')
    [[ "$prefix" =~ ^[A-Za-z0-9_]+$ ]] || return 0
    # (el de produccion, para traer de alli sus imagenes: ps-imagenes)
    local prod
    prod=$(docker_maria_sql "$v" -N -e "SELECT domain FROM \`$db\`.\`${prefix}shop_url\` ORDER BY main DESC, active DESC, id_shop_url LIMIT 1" \
        < /dev/null 2> /dev/null | tr -d '\r' | tr 'A-Z' 'a-z')
    prod=${prod%%:*}
    if valid_domain "$prod" && [[ "$prod" != *.docker.local && "$prod" != *.docker.test && "$prod" != *.local ]]; then
        docker_conf_set "$slug" PRODUCCION "$prod"
    fi
    echo "Tienda PrestaShop: su dominio pasa a $dom en la BBDD de Docker"
    docker_maria_sql "$v" "$db" << EOF
UPDATE \`${prefix}shop_url\` SET domain = '$dom', domain_ssl = '$dom';
UPDATE \`${prefix}configuration\` SET value = '$dom' WHERE name IN ('PS_SHOP_DOMAIN', 'PS_SHOP_DOMAIN_SSL');
UPDATE \`${prefix}configuration\` SET value = '1' WHERE name IN ('PS_SSL_ENABLED', 'PS_SSL_ENABLED_EVERYWHERE');
EOF
}

# docker-nuevo <carpeta> <php> <mariadb> [--bd <base> --desde <version XAMPP-X> | --volcado <fichero>]:
# proyecto en Docker con el Apache de Docker. Su BBDD (vacia, la de una version XAMPP-X o un volcado) va en
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
        [ -n "$db" ] && valid_version_name "$from" && [ -d "$BASE_DIR/XAMPP-$from" ] \
            || { echo "Con --desde hay que decir la base (--bd) y una version XAMPP-X que exista"; return 1; }
    elif [ -n "$db" ] && [ -z "$dump" ]; then
        echo "Con --bd hay que decir de que version XAMPP-X se copia (--desde)"
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
        echo "Ya hay un proyecto en Docker con el nombre $slug (de antes, con XAMPP-X delante): pasalo con lvm-instalador docker-pasar $slug"
        return 1
    fi
    # shellcheck disable=SC2209  # (tipo=otro es un texto, no una orden)
    if is_prestashop "$folder"; then tipo=ps; elif is_wordpress "$folder"; then tipo=wp; else tipo=otro; fi
    if [ $live -eq 1 ]; then
        [ "$tipo" == wp ] && [ -n "$from" ] || { echo "--en-vivo: solo con un WordPress y su BBDD de una version XAMPP-X (--bd y --desde)"; return 1; }
    fi
    dbname=${db:-$(tr '-' '_' <<< "$slug")}
    user=$(cut -c1-32 <<< "nx_$dbname")
    echo "Proyecto en Docker: $folder con PHP $php y MariaDB $maria comun (BBDD $dbname)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $dir con la imagen nexum-php:$php, la BBDD $dbname en $(docker_maria_name "$maria") y $(docker_web_url "$( [ $tipo == ps ] && echo "$slug" || echo "$slug-php${php//./}").docker.local")"
        [ -n "$db" ] && echo "  [simulacion] copia de $db ${from:+de XAMPP-$from}${dump:+de $dump}"
        return 0
    fi
    docker_ready || { echo "Docker Desktop no esta en marcha: abrelo (pestaña Docker) y vuelve a intentarlo."; return 1; }
    if ! docker_web_ports_ok; then
        echo "La direccion $(docker_web_get IP) del Apache de Docker aun no esta en este Mac: pulsa «Permitir» en"
        echo "Configuracion, Docker (o: lvm-instalador docker-web permitir), o elige otra direccion."
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
    # (la clave del proyecto: sin ella sus contenedores de PHP no responden a nadie)
    ( umask 077
      printf 'DB_PASS=%s\nWEB_KEY=%s\n' "$pass" "$(head -c 30 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-32)" > "$dir/.env"
      printf 'MODO=web\nCARPETA=%s\nTIPO=%s\nPHP=%s\nACTIVA=%s\nMARIADB=%s\nBBDD=%s\nUSUARIO=%s\nCONFIG=%s\nESQUEMA=%s\n' \
          "$folder" "$tipo" "$php" "$php" "$maria" "$dbname" "$user" "$rel" "$DOCKER_IMAGE_SCHEMA" > "$dir/proyecto.conf" ) || return 1
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
            echo "Copiando $db de XAMPP-$from..."
            export_database "$db" "$tmp" "$from" || { rm -f "$tmp"; tmp=""; echo "No se ha podido descargar $db de XAMPP-$from: la BBDD queda vacia."; }
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

# docker-nuevo ... --en-vivo: el proyecto sin BBDD en Docker, con la de esa version XAMPP-X en vivo (con el
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
    echo "2/4 BBDD $(docker_conf "$slug" BBDD) de XAMPP-$owner, en vivo (la misma que web.local)"
    lampp_bd_up "$owner" && lampp_bd_bridge_up "$owner" || return 1
    task_step
    echo "3/4 Apache de Docker y $(docker_web_domain "$slug" "$php")"
    docker_web_hosts poner "$(docker_web_pma)" "$(docker_web_domain "$slug" "$php")" || return 1
    docker_web_up || return 1
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d "php${php//./}" || return 1
    task_step
    echo "4/4 Certificado en el navegador"
    docker_web_trust
    echo "Proyecto en Docker listo: $(docker_web_url "$(docker_web_domain "$slug" "$php")") (PHP $php), con la BBDD de XAMPP-$owner en vivo"
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
    docker_ready || { echo "Docker Desktop no esta en marcha"; return 1; }
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

# docker-php-quitar <nombre> <php>: quita una version de PHP de un proyecto (su contenedor, su
# configuracion y su dominio). La ultima no: para eso, borrar el proyecto de Docker
function docker_web_remove() {
    local slug=$1 php=$2 dir list rest dom
    docker_web_project "$slug" || { echo "No hay ningun proyecto en Docker (con el Apache de Docker) con el nombre $slug"; return 1; }
    dir=$DOCKER_DIR/$slug
    list=$(docker_conf "$slug" PHP)
    [[ " $list " == *" $php "* ]] || { echo "$slug no tiene PHP $php"; return 1; }
    rest=$(tr ' ' '\n' <<< "$list" | grep -vxF "$php" | tr '\n' ' ' | sed 's/ $//')
    [ -n "$rest" ] || { echo "PHP $php es la unica version de $slug: para quitarla, borra el proyecto de Docker"; return 1; }
    dom=$(docker_web_domain "$slug" "$php")
    echo "$slug: se quita PHP $php (la carpeta y la BBDD se quedan)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] fuera el contenedor $(docker_web_container "$slug" "$php")"
        return 0
    fi
    docker_dns_on || sudo_first || return 1
    if [ "$(docker_conf "$slug" TIPO)" == ps ] && [ "$(docker_conf "$slug" ACTIVA)" == "$php" ]; then
        docker_web_switch "$slug" "${rest%% *}" || return 1
    fi
    dk compose --project-directory "$dir" -f "$dir/compose.yaml" rm -sf "php${php//./}" > /dev/null 2>&1
    dk volume rm "nexum-${slug}_cache-${php//./}" > /dev/null 2>&1
    rm -f "$dir/config-${php//./}.php"
    docker_conf_set "$slug" PHP "$rest" && docker_web_compose "$slug" || return 1
    # (la que se enseña como suya, si era esa: la siguiente)
    if [ "$(docker_conf "$slug" ACTIVA)" == "$php" ]; then
        docker_conf_set "$slug" ACTIVA "${rest%% *}" && docker_conf_set "$slug" DOMINIO "$(docker_web_domain "$slug" "${rest%% *}")"
    fi
    [ "$(docker_conf "$slug" TIPO)" == ps ] || docker_web_hosts quitar "$dom"
    docker_web_reload
    echo "Listo: $slug sigue con PHP $rest"
}

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
    docker_ready || { echo "Docker Desktop no esta en marcha"; return 1; }
    docker_conf_set "$slug" ACTIVA "$php" || return 1
    docker_web_hosts poner "$(docker_web_domain "$slug" "$php")" || return 1
    docker_maria_up "$(docker_conf "$slug" MARIADB)" && docker_web_compose "$slug" || return 1
    if ! dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d "php${php//./}"; then
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
                docker_web_up && docker_web_compose "$slug" || return 1
            else
                docker_maria_up "$maria" && docker_web_up && docker_web_compose "$slug" || return 1
            fi
            run "${c[@]}" up -d $(docker_web_services "$slug") ;;
        parar) run "${c[@]}" stop && docker_web_idle_stop && lampp_bd_release "$(docker_conf "$slug" LAMPP_BD)" "$slug" ;;
        registros) "${c[@]}" logs --no-color --tail 200 ;;
        borrar)
            local db user domains
            db=$(docker_conf "$slug" BBDD) user=$(docker_conf "$slug" USUARIO)
            mapfile -t domains < <(docker_web_domains "$slug")
            # (con la BBDD de XAMPP-X en vivo, la que se borra es su copia de Docker, si tiene: la de XAMPP-X nunca)
            if [ -n "$(docker_conf "$slug" LAMPP_BD)" ]; then
                db=$(docker_conf "$slug" BBDD_DOCKER) user=$(docker_conf "$slug" USUARIO_DOCKER)
            fi
            echo "Se borran los contenedores de $slug${db:+ y su BBDD $db de la MariaDB $maria de Docker} (la de XAMPP-X no se toca)"
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
            # (los que van en vivo con la BBDD de XAMPP-X no usan la MariaDB comun)
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

