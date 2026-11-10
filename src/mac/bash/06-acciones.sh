# ===========================================================================
# Acciones
# ===========================================================================

# Los vhosts son del administrador: Apache los lee como root al arrancar, y si fueran tuyos
# cualquier programa que se ejecute con tu usuario (un plugin de una web, por ejemplo) podria
# añadirles una orden que se ejecutaria como root (ErrorLog "|orden", LoadModule...). Se edita una
# copia (VHOSTS_COPY) y vhosts --aplicar la comprueba y la escribe con sudo.
VHOSTS_COPY="$HOME/.lvm-instalador/httpd-vhosts.conf"

# Directivas que solo cambian como se sirve cada web. El resto (LoadModule, Include, Listen,
# PidFile, User, RewriteMap, SSLPassPhraseDialog...) se aplicaria como root a todo Apache: no se
# admite en los vhosts (se puede seguir poniendo a mano con sudo -e). Los registros, sin tuberias
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
    # Solo un Include: el de la clave de un proyecto en Docker (lo pone el gestor; el fichero es de
    # root y solo lo lee root)
    if name.lower() == "include" and re.match(r"^\"?/Library/Nexum/XAMPP-compartido/docker-claves/[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?\.conf\"?$", value):
        continue
    if name.lower() not in allowed:
        bad.append("Linea %d: %s no se admite en los vhosts" % (n, name))
        continue
    if name.lower() in logs:
        path = first_arg(value)
        # Solo un fichero dentro de logs (sin subcarpetas ni ..) o syslog
        # (y no con el nombre de un fichero de control de Apache: el .pid lo lee el script lampp)
        # (por /Applications no: el enlace /Applications/XAMPP y los de las versiones de antes de la
        # 1.39.3 los puede cambiar el grupo admin justo cuando Apache, como root, abre el registro.
        # logs/ es lo mismo, y no pasa por el enlace)
        if not (re.match(r"^(logs/|/Library/Nexum/XAMPP-[0-9]+\.[0-9]+(\.[0-9]+)?/xamppfiles/logs/)[A-Za-z0-9._-]+$", path)
                and clean_path(path) and not re.search(r"(?i)(\.pid|\.sock|\.lock|cgisock.*|ssl_mutex.*)$", path)) \
                and not re.match(r"^syslog(:[a-z0-9]+)?$", path):
            bad.append("Linea %d: %s %s: los registros van en la carpeta logs (sin |orden)" % (n, name, path))
    # Certificados y claves solo de las carpetas del gestor: con otra ruta, Apache (que arranca como
    # root) cargaria la clave de otro servicio del equipo
    if name.lower() in ssl_files:
        path = first_arg(value)
        # (uno que ya se usaba tampoco si va por /Applications: lo puede cambiar el grupo admin)
        if not clean_path(path) or (path not in known or path.startswith("/Applications/")) and (not re.match(r"^(/Library/Nexum/XAMPP-compartido/ssl/|etc/ssl\.(crt|key)/|/Library/Nexum/XAMPP-[0-9]+\.[0-9]+(\.[0-9]+)?/xamppfiles/etc/ssl\.(crt|key)/)[A-Za-z0-9._+-]+$", path) or ".." in path):
            bad.append("Linea %d: %s %s: los certificados van en XAMPP-compartido/ssl (los que ya tenias valen; los nuevos, ahi)" % (n, name, path))
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
'

# Los registros y certificados por el enlace (/Applications/XAMPP/xamppfiles/logs/x, como los del
# XAMPP oficial) pasan a logs/x o etc/ssl.crt/x, que es lo mismo sin pasar por el enlace
# (VHOSTS_CHECK_PY ya no los admite). Y las rutas de antes de la 1.39.3 (/Applications/XAMPP-compartido
# y /Applications/XAMPP-X.Y.Z), a las de /Library/Nexum
OLD_LOGS_SED='s#^([[:space:]]*(ErrorLog|CustomLog|TransferLog)[[:space:]]+"?)/Applications/XAMPP/xamppfiles/logs/#\1logs/#
s#^([[:space:]]*SSL(CA)?Certificate(Key|Chain)?File[[:space:]]+"?)/Applications/XAMPP/xamppfiles/etc/ssl\.#\1etc/ssl.#
s#/Applications/XAMPP-compartido/#/Library/Nexum/XAMPP-compartido/#g
s#/Applications/(XAMPP-[0-9]+\.[0-9]+(\.[0-9]+)?)/xamppfiles/#/Library/Nexum/\1/xamppfiles/#g'

# Abre una copia de los vhosts en el editor ($VISUAL, $EDITOR o nano) y la aplica. Con --aplicar
# <copia>, la ventana ya la ha editado: se comprueba (vhosts_check y httpd -t), se guarda el
# anterior en ~/nexum-backups (si esta el ajuste copias-ficheros), se escribe con sudo y se recarga
# Apache si esta en marcha. Si Apache
# no acepta la configuracion nueva, se vuelve a la anterior.
function edit_vhosts() {
    local mode=$1 copy=${2:-$VHOSTS_COPY} real backup answer
    if [ ! -e "$ACTIVE_VHOSTS" ]; then
        echo "No existe $ACTIVE_VHOSTS (se crea al instalar la primera version de PHP)."
        return 1
    fi
    real=$(realpath_f "$ACTIVE_VHOSTS")
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
    if [ "$DRY" -eq 1 ] || [ -z "$SUDO" ]; then
        python3 -I -c "$VHOSTS_CHECK_PY" "$copy" "$real" || return 1
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] copia de root, comprobacion, sudo install en $real, httpd -t y recarga de Apache"
            return 0
        fi
        cp "$real" "$real.anterior" && cp "$copy" "$real" || return 1
        apache_configtest || { cp "$real.anterior" "$real"; return 1; }
        echo "Vhosts actualizados ($real)"
        return 0
    fi
    # La copia editada es tuya y cualquier programa con tu usuario puede cambiarla mientras se
    # escribe la contraseña: se lee una sola vez (con tu usuario) a una carpeta de root, y lo que se
    # comprueba es exactamente lo que se escribe. La version anterior queda tambien en esa carpeta
    local snap
    sudo -v || return 1
    if [ "$real" != "$VHOSTS_FILE" ] || ! vhosts_path_ok; then
        echo "No se cambian los vhosts: $VHOSTS_FILE tiene que ser un fichero normal de $COMMON (sin enlaces)."
        return 1
    fi
    snap=$(sudo mktemp -d /tmp/lvm-vhosts.XXXXXX) || return 1
    sudo chmod 700 "$snap"
    if ! sudo sh -c 'umask 077; sed -E "$2" > "$1"' sh "$snap/nuevo" "$OLD_LOGS_SED" < "$copy" \
            || ! sudo cp "$real" "$snap/anterior"; then
        sudo rm -rf "$snap"
        return 1
    fi
    if ! sudo python3 -I -c "$VHOSTS_CHECK_PY" "$snap/nuevo" "$snap/anterior"; then
        sudo rm -rf "$snap"
        echo "No se aplican: esas lineas cambiarian todo Apache, que arranca como administrador."
        echo "Si de verdad las necesitas, ponlas a mano: sudo -e $real"
        return 1
    fi
    if [ -f "$COPIES_FILES_FLAG" ]; then
        backup="$COPIES_DIR/httpd-vhosts.conf-$(date +%Y%m%d-%H%M%S)"
        mkdir -p -m 700 "$COPIES_DIR" && cp "$real" "$backup" \
            && echo "Copia de los vhosts anteriores: $backup"
    fi
    if ! sudo install -o root -g wheel -m 644 "$snap/nuevo" "$real"; then
        sudo rm -rf "$snap"
        return 1
    fi
    vhosts_root > /dev/null
    if ! apache_configtest; then
        echo "Apache no acepta los vhosts nuevos: se deja como estaba."
        sudo install -o root -g wheel -m 644 "$snap/anterior" "$real"
        sudo rm -rf "$snap"
        return 1
    fi
    sudo rm -rf "$snap"
    echo "Vhosts actualizados ($real)"
    if [ -f "$LINK/xamppfiles/logs/httpd.pid" ]; then
        echo "Recargando Apache..."
        xampp_ctl reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi
}

# Comprueba la configuracion de Apache de la version montada (httpd -t, como root porque lee las
# claves de los certificados). Si no la acepta, muestra el error. Sin version montada, con la primera
# instalada (todas leen el mismo fichero de vhosts).
function apache_configtest() {
    local dir out d
    dir=$(active_dir)
    # Root ejecuta su httpd: solo el de una version de root (si no, el enlace /Applications/XAMPP o
    # una carpeta XAMPP-0.1 puesta por otro programa haria que root ejecutara lo suyo)
    if [ -n "$SUDO" ] && [ -z "$TEST_DIR" ] && [ -n "$dir" ] && ! trusted_version_dir "$dir"; then
        dir=""
    fi
    if [ -z "$dir" ]; then
        for d in $(version_dirs); do
            { [ -z "$SUDO" ] || [ -n "$TEST_DIR" ] || trusted_version_dir "$d"; } && { dir=$d; break; }
        done
    fi
    [ -n "$dir" ] && [ -x "$dir/xamppfiles/apache2/bin/httpd" ] || return 0
    out=$($SUDO "$dir/xamppfiles/apache2/bin/httpd" -t -f "$dir/xamppfiles/etc/httpd.conf" 2>&1) && return 0
    sed 's/^/  /' <<< "$out" | tail -5
    return 1
}

# ¿Puede root escribir en los vhosts compartidos? Solo si es el fichero de XAMPP-compartido, sin
# enlaces (ni la carpeta, ni el fichero, ni un enlace duro): en /Applications puede escribir
# cualquier administrador, y con XAMPP-compartido cambiada por una carpeta con un enlace, un
# programa con tu usuario haria que root escribiera en otro fichero (/etc/sudoers). Lo que se
# escribe se comprueba aparte (VHOSTS_CHECK_PY); unos vhosts tuyos de versiones antiguas valen
function vhosts_path_ok() {
    [ -n "$SUDO" ] && [ -z "$TEST_DIR" ] || return 0
    [ "$(dirname "$VHOSTS_FILE")" == "$COMMON" ] && [ -d "$COMMON" ] && [ ! -L "$COMMON" ] \
        && [ -f "$VHOSTS_FILE" ] && [ ! -L "$VHOSTS_FILE" ] && [ "$(stat -f %l "$VHOSTS_FILE")" == 1 ]
}

# Los vhosts compartidos, su carpeta y los certificados (ssl) vuelven a ser del administrador si
# alguna version anterior los hizo tuyos. Antes se comprueba lo que llevan, igual que al editarlos:
# Apache los lee como root, y unos vhosts tuyos los podria haber cambiado otro programa (o
# XAMPP-compartido podria ser una carpeta puesta por el). Devuelve 0 si ha cambiado algo.
function vhosts_root() {
    local real dir snap
    real=$(realpath_f "$VHOSTS_FILE")
    [ -f "$real" ] && [[ "$real" == "$BASE_DIR"/* ]] || return 1
    dir=$(dirname "$real")
    [ "$(stat -f %u "$real")" == 0 ] && [ "$(stat -f %u "$dir")" == 0 ] \
        && { [ ! -d "$dir/ssl" ] || [ "$(stat -f %u "$dir/ssl")" == 0 ]; } && return 1
    if [ "$real" != "$COMMON/httpd-vhosts.conf" ] || [ -L "$COMMON" ] || [ -L "$VHOSTS_FILE" ] \
            || [ "$(stat -f %l "$real")" != 1 ] || [ -L "$dir/ssl" ]; then
        echo "Los vhosts ($VHOSTS_FILE) no son del administrador y no estan donde deben (enlaces): no se tocan."
        echo "Revisa $COMMON a mano."
        return 1
    fi
    echo "Los vhosts ($real) vuelven a ser del administrador: Apache los lee como root al arrancar"
    [ "$DRY" -eq 1 ] && return 0
    # Se leen una vez a una carpeta de root, se comprueban y se escribe eso mismo
    snap=$($SUDO mktemp -d /tmp/lvm-vhosts.XXXXXX) && $SUDO chmod 700 "$snap" || return 1
    # (sin certificados «conocidos»: los de unos vhosts tuyos no se dan por buenos solo por estar ahi)
    if ! $SUDO sh -c 'umask 077; sed -E "$2" > "$1"' sh "$snap/v" "$OLD_LOGS_SED" < "$real" \
            || ! $SUDO /usr/bin/python3 -I -c "$VHOSTS_CHECK_PY" "$snap/v"; then
        $SUDO rm -rf "$snap"
        echo "Los vhosts llevan lineas que cambiarian todo Apache (que arranca como root): no se pasan al"
        echo "administrador. Quitalas con Editar vhosts o a mano en $real."
        return 1
    fi
    run $SUDO chown root:wheel "$dir" && run $SUDO chmod 755 "$dir" \
        && run $SUDO install -o root -g wheel -m 644 "$snap/v" "$real" || { $SUDO rm -rf "$snap"; return 1; }
    $SUDO rm -rf "$snap"
    # La carpeta ssl: no se cambia de dueño lo que hay (macOS no protege los enlaces duros y chown
    # no quita el setuid, y un programa tuyo podria cambiarla mientras tanto). Root hace una nueva y
    # copia solo los certificados y claves normales, leyendolos sin seguir enlaces; la anterior
    # queda apartada al lado
    if [ -d "$dir/ssl" ] && [ "$(stat -f %u "$dir/ssl")" != 0 ]; then
        local new stamp=$(date +%Y%m%d-%H%M%S)
        new=$($SUDO mktemp -d "$dir/.ssl-nueva.XXXXXX") && $SUDO chmod 755 "$new" \
            && $SUDO /usr/bin/python3 -I -c "$SSL_COPY_PY" "$dir/ssl" "$new" \
            && $SUDO mv "$dir/ssl" "$dir/ssl.anterior-$stamp" && $SUDO mv "$new" "$dir/ssl" || {
                [ -n "$new" ] && $SUDO rm -rf "$new"
                echo "No se ha podido pasar $dir/ssl al administrador."
                return 0
            }
        # Si Apache no arranca con la nueva (un vhost usaba algo que no se ha copiado), se vuelve a la de antes
        if ! apache_configtest; then
            $SUDO mv "$dir/ssl" "$dir/.ssl-descartada-$stamp" && $SUDO mv "$dir/ssl.anterior-$stamp" "$dir/ssl"
            echo "Apache no acepta los vhosts con la carpeta ssl nueva: se ha dejado la de antes. Revisa $dir/ssl."
            return 0
        fi
        echo "Certificados de $dir/ssl copiados a una carpeta del administrador (la anterior: ssl.anterior-$stamp)"
    fi
    return 0
}

# Copia de los certificados de una carpeta ssl tuya a una de root: solo ficheros normales (sin
# enlaces simbolicos ni duros), con nombres de certificado, abiertos sin seguir enlaces. Las claves
# con 600 y lo demas con 644. Uso: <origen> <destino de root>
SSL_COPY_PY='
import os, re, stat, sys
src, dst = sys.argv[1], sys.argv[2]
for name in sorted(os.listdir(src)):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", name):
        print("  No se copia %s (nombre raro)" % name.encode("ascii", "replace").decode())
        continue
    try:
        fd = os.open(os.path.join(src, name), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        print("  No se copia %s (enlace o no se puede leer)" % name)
        continue
    with os.fdopen(fd, "rb") as f:
        st = os.fstat(f.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1 or st.st_size > 1000000:
            print("  No se copia %s (no es un certificado normal)" % name)
            continue
        data = f.read(1000000)
    # (solo los certificados se pueden leer: las claves, tambien las de mkcert (-key.pem), solo root)
    low = name.lower()
    mode = 0o644 if (low.endswith((".crt", ".cer", ".pem")) and "key" not in low) else 0o600
    out = os.open(os.path.join(dst, name), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    with os.fdopen(out, "wb") as o:
        o.write(data)
'


# Edita /etc/hosts. Sin argumentos, con sudo -e. Con --aplicar <copia>, la ventana ya ha editado
# una copia: comprueba que sigue teniendo localhost, guarda el /etc/hosts actual en ~/nexum-backups
# (si esta el ajuste copias-ficheros), escribe la copia encima (con sudo si hace falta; se conservan dueño y permisos) y vacia la cache
# de DNS de macOS
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
    if ! grep -qE '^[[:space:]]*(127\.0\.0\.1|::1)[[:space:]](.*[[:space:]])?localhost([[:space:]]|$)' "$check"; then
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
    # github.com a un servidor falso) se pone a mano con: nexum hosts
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
    if not (ip.startswith("127.") or ip in ("::1", "0.0.0.0", "fe80::1%lo0")):
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
        echo "No se cambia $HOSTS_FILE. Si son tuyas, ponlas en la terminal con: nexum hosts"
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
        [ "$HOSTS_FILE" == /etc/hosts ] && { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; } 2> /dev/null
    fi
    echo "$HOSTS_FILE actualizado"
    browser_trust --hosts || true
}

# Nombre de version valido (8.4, 8.3.10...): sin barras ni .. que lleven a otra carpeta
function valid_version_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ "$1" != *..* ]]
}

function use_version() {
    local version=$1
    local dir=$BASE_DIR/XAMPP-$version

    if ! valid_version_name "$version" || [ ! -d "$dir" ] || [ -L "$dir" ] || [ ! -f "$dir/xamppfiles/etc/pvm-stack" ]; then
        if valid_version_name "$version" && [ -z "$TEST_DIR" ] && [ -d "$LEGACY_DIR/XAMPP-$version" ] && [ ! -L "$LEGACY_DIR/XAMPP-$version" ]; then
            echo "XAMPP-$version sigue en $LEGACY_DIR (de antes de la 1.39.3), donde la puede cambiar el grupo admin:"
            echo "pasala a $BASE_DIR con: nexum migrar"

            return 1
        fi
        echo "No existe la version $version"

        return 1
    fi

    if official_xampp; then
        echo "$LINK es un XAMPP oficial y no un enlace. Apartalo primero desde el panel."

        return 1
    fi

    # PHP2Shell: se avisa (la ventana ya lo ha preguntado antes)
    case "$(php2shell_state "$(php_version "$dir")" "$dir")" in
        actualizable) echo "Aviso: PHP $(php_version "$dir") es vulnerable a PHP2Shell (CVE-2026-109618/109619): pasala al ultimo parche de su rama con nexum actualizar $version (o instala el parche a su lado y nexum pasar-version)." ;;
        parcheable) echo "Aviso: PHP $(php_version "$dir") es vulnerable a PHP2Shell: nexum actualizar $version le pone el parche de seguridad." ;;
        sin-arreglo) echo "Aviso: PHP $(php_version "$dir") es vulnerable a PHP2Shell y no tiene arreglo: usala solo con proyectos de confianza." ;;
    esac

    local before
    before=$(active_dir)
    [ -L "$LINK" ] && run xampp_ctl stop
    [ -L "$LINK" ] && run $SUDO rm "$LINK"
    # Lo que no se haya cerrado al parar (de esta version o de otras anteriores) no puede seguir en
    # memoria al montar la nueva
    close_processes --todos
    # (la BBDD de la que se deja, si la usa en vivo un proyecto de Docker: su MariaDB sigue, en otro puerto)
    [ -n "$before" ] && [ "$before" != "$dir" ] && lampp_bd_keep "$before"
    # Solo para este Mac (lo que falte), antes de arrancarla; tambien las demas versiones. Si no se
    # puede, no se arranca
    secure_all
    if [ $? -eq 2 ] && [ "$DRY" -eq 0 ]; then
        echo "No se arranca XAMPP-$version: no se ha podido dejar solo para este Mac."
        echo "Prueba con: nexum asegurar --todas"
        return 1
    fi
    vhosts_root
    # (-h: si en este momento hubiera una carpeta en su lugar, se crearia el enlace dentro y no se
    # arrancaria esta version: se comprueba)
    run $SUDO ln -sh "$dir" "$LINK"
    if [ "$DRY" -eq 0 ] && { [ ! -L "$LINK" ] || [ "$(readlink "$LINK")" != "$dir" ]; }; then
        echo "$LINK no es el enlace a $dir (algo lo ha cambiado): no se arranca."
        return 1
    fi
    lampp_bd_handover "$dir"
    run xampp_ctl start
    lampp_bd_retarget "$dir"
    # MariaDB: sin usuarios anonimos ni permisos de cualquiera en las bases test
    [ "$DRY" -eq 0 ] && wait_mariadb && secure_mariadb
    # (el correo de pruebas va con la version)
    mailpit_sync

    echo "Usando XAMPP-$version (PHP $(php_version "$dir"))"
}

