# ===========================================================================
# Acciones de lvm
# ===========================================================================

# Los vhosts son del administrador: Apache los lee como root al arrancar, y si fueran tuyos
# cualquier programa que se ejecute con tu usuario (un plugin de una web, por ejemplo) podria
# añadirles una orden que se ejecutaria como root (ErrorLog "|orden", LoadModule...). Se edita una
# copia (VHOSTS_COPY) y vhosts --aplicar la comprueba y la escribe con sudo.
VHOSTS_COPY="$HOME/.lvm-instalador/httpd-vhosts.conf"

# Directivas que solo cambian como se sirve cada web. El resto (LoadModule, Include, Listen,
# PidFile, User, RewriteMap, SSLPassPhraseDialog...) se aplicaria como root a todo Apache: no se
# admite en los vhosts (se puede seguir poniendo a mano con sudoedit). Los registros, sin tuberias
# (|orden) y dentro de la carpeta logs.
VHOSTS_CHECK_PY='
import re, sys
allowed = {d.lower() for d in """
VirtualHost IfModule IfDefine IfVersion Directory DirectoryMatch Location LocationMatch Files
FilesMatch Proxy ProxyMatch Limit LimitExcept RequireAll RequireAny RequireNone If ElseIf Else
ServerName ServerAlias ServerAdmin ServerPath DocumentRoot UseCanonicalName ServerSignature
ErrorLog CustomLog TransferLog LogLevel LogFormat
SSLEngine SSLCertificateFile SSLCertificateKeyFile SSLCertificateChainFile SSLCACertificateFile
SSLProtocol SSLCipherSuite SSLHonorCipherOrder SSLProxyEngine SSLProxyVerify SSLProxyCheckPeerName
SSLProxyCheckPeerCN SSLProxyCheckPeerExpire SSLOptions
Header RequestHeader Options AllowOverride AllowOverrideList Require Order Allow Deny Satisfy
DirectoryIndex DirectorySlash FallbackResource AcceptPathInfo ErrorDocument
RewriteEngine RewriteRule RewriteCond RewriteBase RewriteOptions
Redirect RedirectMatch RedirectPermanent RedirectTemp Alias AliasMatch ScriptAlias ScriptAliasMatch
ProxyPass ProxyPassReverse ProxyPassMatch ProxyPreserveHost ProxyRequests ProxyTimeout ProxyAddHeaders
SetEnv SetEnvIf SetEnvIfNoCase UnsetEnv PassEnv BrowserMatch BrowserMatchNoCase
SetHandler AddHandler RemoveHandler AddType ForceType AddDefaultCharset AddCharset AddEncoding
AddOutputFilterByType SetOutputFilter SetInputFilter DeflateCompressionLevel
ExpiresActive ExpiresByType ExpiresDefault
php_value php_admin_value php_flag php_admin_flag
KeepAlive KeepAliveTimeout MaxKeepAliveRequests Timeout LimitRequestBody LimitRequestFields
AllowEncodedSlashes Protocols H2Direct H2Push EnableSendfile EnableMMAP FileETag
AuthType AuthName AuthUserFile AuthGroupFile AuthBasicProvider NameVirtualHost
""".split()}
logs = {"errorlog", "customlog", "transferlog"}
ssl_files = {"sslcertificatefile", "sslcertificatekeyfile", "sslcertificatechainfile", "sslcacertificatefile"}
bad = []
# Primer argumento de una directiva, entero, como lo lee Apache: entre comillas puede llevar espacios
# ("logs/x /../../etc/y" es una sola ruta, que Apache resuelve con los ..). Se devuelve entero
# (Apache solo separa por espacios ASCII: uno Unicode, como U+00A0, va dentro de la ruta. Las \
# se dejan tal cual: clean_path no las admite)
def first_arg(value):
    value = value.strip(" \t\r\n\v\f")
    if value[:1] in ("\"", "\x27"):
        end = value.find(value[0], 1)
        return value[1:end] if end > 0 else value[1:]
    words = re.split(r"[ \t\r\n\v\f]+", value)
    return words[0] if words else ""
# Una ruta sin espacios ni .. ni /./ ni // (lo que Apache resolveria fuera de la carpeta)
def clean_path(path):
    return path != "" and path.isascii() and not any(c.isspace() for c in path) and "\\" not in path \
        and ".." not in path and "/./" not in path and "//" not in path and not path.startswith("./")
# Los certificados que ya usan los vhosts de ahora (segundo argumento) se siguen admitiendo aunque
# esten en otra carpeta: solo se rechaza una ruta nueva fuera de las del gestor
known = set()
if len(sys.argv) > 2:
    try:
        for l in open(sys.argv[2], encoding="utf-8", errors="replace"):
            w = l.split()
            if len(w) >= 2 and w[0].lower() in ssl_files:
                known.add(first_arg(l.strip()[len(w[0]):]))
    except OSError:
        pass
# Se lee como Apache: por bytes, cada linea hasta \n. Un byte de control (como \0, que corta la
# linea para Apache pero no para Python) haria que los dos vieran lineas distintas: no se admite
data = open(sys.argv[1], "rb").read()
for n, raw in enumerate(data.split(b"\n"), 1):
    if any(c < 32 and c not in (9, 13) or c == 127 for c in raw):
        print("Linea %d: lleva caracteres de control (como \\0): no se admite" % n)
        sys.exit(1)
lines = [l[:-1] if l.endswith("\r") else l for l in data.decode("utf-8", "replace").split("\n")]
i = 0
while i < len(lines):
    n, line = i + 1, lines[i]
    # Lineas partidas con \ al final
    while line.endswith("\\") and i + 1 < len(lines):
        i += 1
        line = line[:-1] + lines[i]
    i += 1
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    # Apache sustituye ${VAR} antes de leer la linea: una ruta que parece buena podria ser otra
    if "${" in s:
        bad.append("Linea %d: las variables ${...} no se admiten en los vhosts" % n)
        continue
    m = re.match(r"<?/?\s*([A-Za-z_][\w-]*)\s*(.*?)>?$", s)
    name, value = (m.group(1), m.group(2).strip()) if m else (s, "")
    if name.lower() not in allowed:
        bad.append("Linea %d: %s no se admite en los vhosts" % (n, name))
        continue
    if name.lower() in logs:
        path = first_arg(value)
        # Solo un fichero dentro de logs (sin subcarpetas ni ..) o syslog
        # (y no con el nombre de un fichero de control de Apache: el .pid lo lee el script lampp)
        if not (re.match(r"^(logs/|/opt/lampp(-[A-Za-z0-9._-]+)?/logs/)[A-Za-z0-9._-]+$", path)
                and clean_path(path) and not re.search(r"(?i)(\.pid|\.sock|\.lock|cgisock.*|ssl_mutex.*)$", path)) \
                and not re.match(r"^syslog(:[a-z0-9]+)?$", path):
            bad.append("Linea %d: %s %s: los registros van en la carpeta logs (sin |orden)" % (n, name, path))
    # Certificados y claves solo de las carpetas del gestor: con otra ruta, Apache (que arranca como
    # root) cargaria la clave de otro servicio del equipo
    if name.lower() in ssl_files:
        path = first_arg(value)
        if not clean_path(path) or path not in known and (not re.match(r"^(/opt/config/ssl/|etc/ssl\.(crt|key)/|/opt/lampp(-[A-Za-z0-9._-]+)?/etc/ssl\.(crt|key)/)[A-Za-z0-9._+-]+$", path) or ".." in path):
            bad.append("Linea %d: %s %s: los certificados van en /opt/config/ssl (los que ya tenias valen; los nuevos, ahi)" % (n, name, path))
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
'

# Abre una copia de los vhosts en el editor ($VISUAL, $EDITOR o nano) y la aplica. Con --aplicar
# <copia>, la ventana ya la ha editado: se comprueba (vhosts_check y httpd -t), se guarda el
# anterior en ~/nexum-backups (si esta el ajuste copias-ficheros), se escribe con sudo y se recarga
# Apache si esta en marcha. Si Apache
# no acepta la configuracion nueva, se vuelve a la anterior.
function edit_vhosts() {
    local mode=$1 copy=${2:-$VHOSTS_COPY} real backup answer
    if [ ! -e "$ACTIVE_VHOSTS" ]; then
        echo "No hay ninguna version activa con $ACTIVE_VHOSTS. Activa una version primero."
        return 1
    fi
    real=$(readlink -f "$ACTIVE_VHOSTS")
    # Las ventanas de versiones anteriores pedian permiso para hacerlo tuyo: ya no hace falta
    [ "$mode" == "--permiso" ] && return 0
    if [ "$mode" != "--aplicar" ]; then
        mkdir -p -m 700 "$(dirname "$copy")" && cp "$real" "$copy" || return 1
        run ${VISUAL:-${EDITOR:-nano}} "$copy"
        if cmp -s "$copy" "$real"; then
            echo "No hay cambios en los vhosts."
            return 0
        fi
        read -r -p "¿Aplicar los cambios? [s/N]: " answer
        [[ "$answer" =~ ^[sSyY]$ ]] || { echo "No se ha cambiado nada (la copia queda en $copy)"; return 0; }
    fi
    if [ ! -s "$copy" ]; then
        echo "La copia editada ($copy) no existe o esta vacia: no se cambian los vhosts."
        return 1
    fi
    if cmp -s "$copy" "$real"; then
        echo "No hay cambios en los vhosts."
        return 0
    fi
    if [ "$DRY" -eq 1 ]; then
        python3 -I -c "$VHOSTS_CHECK_PY" "$copy" "$real" || return 1
        echo "  [simulacion] copia de root, comprobacion, sudo install en $real, httpd -t y recarga de Apache"
        return 0
    fi
    # La copia editada es tuya y cualquier programa con tu usuario puede cambiarla mientras se
    # escribe la contraseña: se lee una sola vez (con tu usuario) a una carpeta de root, y lo que se
    # comprueba es exactamente lo que se escribe. La version anterior queda tambien en esa carpeta
    # (la de ~/nexum-backups es solo para ti: no se vuelve a escribir desde ahi)
    local snap
    sudo -v || return 1
    snap=$(sudo mktemp -d /tmp/lvm-vhosts.XXXXXX) || return 1
    sudo chmod 700 "$snap"
    if ! sudo sh -c 'umask 077; cat > "$1"' sh "$snap/nuevo" < "$copy" \
            || ! sudo cp "$real" "$snap/anterior"; then
        sudo rm -rf "$snap"
        return 1
    fi
    if ! sudo python3 -I -c "$VHOSTS_CHECK_PY" "$snap/nuevo" "$snap/anterior"; then
        sudo rm -rf "$snap"
        echo "No se aplican: esas lineas cambiarian todo Apache, que arranca como administrador."
        echo "Si de verdad las necesitas, ponlas a mano: sudoedit $real"
        return 1
    fi
    if [ -f "$COPIES_FILES_FLAG" ]; then
        backup="$COPIES_DIR/httpd-vhosts.conf-$(date +%Y%m%d-%H%M%S)"
        mkdir -p -m 700 "$COPIES_DIR" && cp "$real" "$backup" \
            && echo "Copia de los vhosts anteriores: $backup"
    fi
    if ! sudo install -o root -g root -m 644 "$snap/nuevo" "$real"; then
        sudo rm -rf "$snap"
        return 1
    fi
    vhosts_root > /dev/null
    if ! apache_configtest; then
        echo "Apache no acepta los vhosts nuevos: se deja como estaba."
        sudo install -o root -g root -m 644 "$snap/anterior" "$real"
        sudo rm -rf "$snap"
        return 1
    fi
    sudo rm -rf "$snap"
    echo "Vhosts actualizados ($real)"
    if [ -f /opt/lampp/logs/httpd.pid ]; then
        echo "Recargando Apache..."
        sudo /opt/lampp/lampp reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi
}

# Comprueba la configuracion de Apache de la version montada (httpd -t, como root porque lee las
# claves de los certificados). Si no la acepta, muestra el error.
function apache_configtest() {
    local httpd=/opt/lampp/bin/httpd out
    [ -x /opt/lampp/apache2/bin/httpd ] && httpd=/opt/lampp/apache2/bin/httpd
    [ -x "$httpd" ] || return 0
    out=$(sudo "$httpd" -f /opt/lampp/etc/httpd.conf -t 2>&1) && return 0
    sed 's/^/  /' <<< "$out" | tail -5
    return 1
}

# /opt tiene que ser del administrador: si es tuyo, cualquier programa con tu usuario (el PHP de
# una web) puede cambiar el enlace /opt/lampp, una version o /opt/lvm-instalador, y lo siguiente que
# se arranque con sudo seria suyo. Solo se cambia /opt; sus carpetas (htdocs, programas) siguen
# siendo de quien eran. Devuelve 0 si ha cambiado algo.
function opt_root() {
    [ -n "$TEST_DIR" ] && return 1
    [ -d /opt ] && [ ! -L /opt ] || return 1
    [ "$(stat -c %u /opt)" == 0 ] && [ -z "$(find /opt -maxdepth 0 -perm /022)" ] && return 1
    echo "/opt vuelve a ser del administrador (sus carpetas siguen siendo de quien eran)"
    run sudo chown root:root /opt || return 1
    run sudo chmod 755 /opt
    return 0
}

# Los vhosts compartidos (y su carpeta, con los certificados de web.local) vuelven a ser del
# administrador si alguna version anterior los hizo tuyos. Tambien /opt (opt_root). Devuelve 0 si
# ha cambiado algo.
function vhosts_root() {
    local real dir changed=1
    opt_root && changed=0
    real=$(readlink -f "$VHOSTS_FILE")
    [ -f "$real" ] && [[ "$real" == /opt/* ]] || return $changed
    dir=$(dirname "$real")
    [ "$(stat -c %u "$real")" == 0 ] && [ "$(stat -c %u "$dir")" == 0 ] && return $changed
    echo "Los vhosts ($real) vuelven a ser del administrador: Apache los lee como root al arrancar"
    run sudo chown root:root "$dir" "$real" || return 1
    run sudo chmod 755 "$dir"
    run sudo chmod 644 "$real"
    [ -d "$dir/ssl" ] && run sudo chown -R root:root "$dir/ssl"
    return 0
}

# Edita /etc/hosts. Sin argumentos, con sudoedit (sudo -e). Con --aplicar <copia>, la ventana ya
# ha editado una copia: comprueba que sigue teniendo localhost, guarda el /etc/hosts actual en
# ~/nexum-backups (si esta el ajuste copias-ficheros) y escribe la copia encima (con sudo si hace
# falta; se conservan dueño y permisos)
function edit_hosts() {
    local s=""
    [ -w "$HOSTS_FILE" ] || s=sudo
    if [ "$1" != "--aplicar" ]; then
        local rc
        if [ -n "$s" ]; then
            run sudo -e "$HOSTS_FILE"
        else
            run ${VISUAL:-${EDITOR:-nano}} "$HOSTS_FILE"
        fi
        rc=$?
        # (el navegador deja de aceptar las tiendas que ya no estan falseadas: browser_trust)
        browser_trust --hosts || true
        return $rc
    fi
    local copy=$2 backup="$COPIES_DIR/hosts-$(date +%Y%m%d-%H%M%S)" snap="" check
    # (aparte: en la misma linea, $copy aun seria el de fuera)
    check=$copy
    if [ ! -s "$copy" ]; then
        echo "La copia editada ($copy) no existe o esta vacia: no se cambia $HOSTS_FILE."
        return 1
    fi
    # Con sudo, la copia (tuya) se lee una sola vez a una carpeta de root: lo que se comprueba es lo
    # que se escribe, aunque otro programa con tu usuario la cambie mientras escribes la contraseña
    if [ -n "$s" ] && [ "$DRY" -eq 0 ]; then
        sudo -v || return 1
        snap=$(sudo mktemp -d /tmp/lvm-hosts.XXXXXX) || return 1
        sudo chmod 755 "$snap"
        if ! sudo sh -c 'umask 022; cat > "$1"' sh "$snap/hosts" < "$copy"; then
            sudo rm -rf "$snap"
            return 1
        fi
        check=$snap/hosts
        LVM_HOSTS_SNAP=$snap
        trap 'sudo rm -rf "$LVM_HOSTS_SNAP"; trap - RETURN' RETURN
    fi
    if ! grep -qE '^[[:space:]]*(127\.0\.0\.1|::1)[[:space:]].*\blocalhost\b' "$check"; then
        echo "La copia editada no tiene la linea de localhost (127.0.0.1 localhost): no se cambia"
        echo "$HOSTS_FILE, porque el equipo dejaria de encontrarse a si mismo."
        return 1
    fi
    if cmp -s "$check" "$HOSTS_FILE"; then
        echo "No hay cambios en $HOSTS_FILE."
        return 0
    fi
    # La copia se puede cambiar con tu usuario: solo se aceptan lineas nuevas que lleven a este
    # equipo (lo que usa la aplicacion). Una que lleve un dominio a otra direccion (por ejemplo,
    # github.com a un servidor falso) se pone a mano con: lvm-instalador hosts
    local other
    other=$(python3 -I - "$HOSTS_FILE" "$check" <<'EOF'
import sys
def active(path):
    out = set()
    # Las lineas, solo por \n (como las lee el sistema: un \r suelto no corta la linea)
    for line in open(path, encoding="utf-8", errors="replace", newline="\n"):
        f = line.split("#", 1)[0].split()
        if len(f) >= 2:
            out.add((f[0], tuple(f[1:])))
    return out
old = active(sys.argv[1])
for ip, names in sorted(active(sys.argv[2]) - old):
    if not (ip.startswith("127.") or ip in ("::1", "0.0.0.0")):
        print("  %s %s" % (ip, " ".join(names)))
EOF
)
    # Caracteres de control (como \0, que corta la linea para el sistema pero no para Python, o un \r
    # que no va antes de \n: Python cortaria ahi la linea y el sistema no)
    if ! python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read().replace(b"\r\n", b"\n")
sys.exit(1 if any(c < 32 and c not in (9, 10) or c == 127 for c in d) else 0)' "$check"; then
        echo "La copia editada lleva caracteres de control: no se cambia $HOSTS_FILE."
        return 1
    fi
    if [ -n "$other" ]; then
        echo "La copia editada lleva dominios a otros equipos:"
        echo "$other"
        echo "No se cambia $HOSTS_FILE. Si son tuyas, ponlas en la terminal con: lvm-instalador hosts"
        return 1
    fi
    if [ -f "$COPIES_FILES_FLAG" ]; then
        run mkdir -p -m 700 "$COPIES_DIR"
        run cp "$HOSTS_FILE" "$backup" || return 1
        echo "Copia del $HOSTS_FILE anterior: $backup"
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $s tee $HOSTS_FILE < $copy"
    else
        $s tee "$HOSTS_FILE" < "$check" > /dev/null || return 1
    fi
    echo "$HOSTS_FILE actualizado"
    browser_trust --hosts || true
}

# Nombre de version valido (8.4, 8.2.4, 7.1.33...): sin barras ni .. que lleven a otra carpeta
function valid_version_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ "$1" != *..* ]]
}

function use_lampp() {
    local version=$1

    if ! valid_version_name "$version" || [ ! -d "/opt/lampp-$version" ] || [ -L "/opt/lampp-$version" ]; then
        echo "No existe la version $version de lampp en el sistema"

        return 1
    fi

    if [ -d "/opt/lampp" ] && [ ! -L "/opt/lampp" ]; then
        echo "La carpeta /opt/lampp es una instalacion completa y no un enlace. Registrala primero con: lvm-instalador add <nombre>"

        return 1
    fi

    # (se monta igual, avisando: la ventana lo pregunta antes)
    local p2s
    p2s=$(php2shell_state "/opt/lampp-$version" "$(stack_fields "/opt/lampp-$version" | cut -d'|' -f1)")
    if [[ "$p2s" == vulnerable\|* ]]; then
        echo "Aviso: lampp-$version es vulnerable a PHP2Shell (${p2s#*|})."
        echo "  Usala solo con proyectos tuyos y pasa a una version con el arreglo (lvm-instalador actualizar-a)."
    fi

    local before
    before=$(active_dir)
    [ -L /opt/lampp ] && run sudo /opt/lampp/lampp stop
    [ -L /opt/lampp ] && run sudo unlink /opt/lampp
    # Lo que no se haya cerrado al parar (de esta version o de otras anteriores) no puede seguir en
    # memoria al montar la nueva
    close_processes --todos
    # (la BBDD de la que se deja, si la usa en vivo un proyecto de Docker: su MariaDB sigue, sin red)
    [ -n "$before" ] && [ "$before" != "/opt/lampp-$version" ] && lampp_bd_keep "$before"
    # Solo para este equipo (lo que falte), antes de arrancarla. Tambien las demas versiones, por si
    # se arrancan a mano. Si no se puede, no se arranca: quedaria abierta a la red
    secure_all
    if [ $? -eq 2 ] && [ "$DRY" -eq 0 ]; then
        echo "No se arranca lampp-$version: no se ha podido dejar solo para este equipo."
        echo "Prueba con: lvm-instalador asegurar --todas"
        return 1
    fi
    vhosts_root
    run sudo ln -s "/opt/lampp-$version" /opt/lampp
    lampp_bd_handover "/opt/lampp-$version"
    run sudo /opt/lampp/lampp start
    # MariaDB de XAMPP: sin el usuario anonimo ni los permisos de cualquiera en las bases test
    [ "$DRY" -eq 0 ] && wait_mariadb && secure_mariadb
    # (el correo de pruebas va con la version)
    mailpit_sync

    echo "Usando lampp $version"
}

