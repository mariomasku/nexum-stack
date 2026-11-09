# ===========================================================================
# Que el navegador acepte el certificado propio de cada proyecto
# ===========================================================================
# Con el aviso de certificado (La conexion no es privada) el navegador no deja entrar a las
# herramientas que lo manejan (Claude in Chrome y parecidas): no pueden aceptar el aviso. Se confia en
# el certificado de cada proyecto, no en una CA, y solo en uno que no le valga a nadie para otra web.
TRUST_PY='# Certificados propios de los proyectos https y si el navegador ya confia en ellos. Imprime:
#   T|dominio|crt|sha1|1 o 0|real   se puede confiar en el (1: el navegador ya confia; real: 1 si
#                                   es el dominio real de una tienda, falseado en hosts)
#   X|dominio|motivo                no se confia en el
#   U|dominio (Linux)               el navegador acepta uno nuestro con ese nombre en el que ya no
#   U|dominio|copia|sha1|1 o 0 (Mac)  se puede confiar: hay que quitarlo (Mac: 0, ya no lo acepta)
# Solo vale uno autofirmado que no es de CA, solo para su dominio y su alias (www), de root en la
# carpeta de certificados del gestor y con la clave solo para root: confiar en el no deja falsificar
# ninguna otra web. El de un dominio real (una tienda), solo mientras el y su alias esten falseados en
# hosts: Apache corre con tu usuario y tiene la clave en memoria, donde la puede leer el PHP de
# cualquier web, y con ella se podria suplantar la web de verdad; mientras esta falseado, el navegador
# no va a la web de verdad, y al dejar de falsearlo sale con U (se quita)
# TRUST_PY <linux|mac> <puerto https> <carpeta de certificados> [dominio]; los vhosts en LVM_INFO,
# hosts en LVM_HOSTS_FILE y (Mac) las copias de los que se han confiado en LVM_TRUST_DIR
import base64, glob, hashlib, os, plistlib, re, stat, subprocess, sys, tempfile
osname, https, ssldir = sys.argv[1], sys.argv[2], os.path.realpath(sys.argv[3])
only = sys.argv[4] if len(sys.argv) > 4 else ""
HOME = os.path.expanduser("~")
# (LVM_PRUEBA_DUENO: el usuario que hace de root, solo para las pruebas)
ROOT = int(os.environ.get("LVM_PRUEBA_DUENO", "") or 0)
def run(args, data=None):
    kw = {"input": data} if data is not None else {"stdin": subprocess.DEVNULL}
    try:
        r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20,
                           start_new_session=True, **kw)
        return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""
def pems(text):
    return re.findall(r"-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\s]+?-----END CERTIFICATE-----", text)
def sha1(pem):
    der = base64.b64decode("".join(l for l in pem.splitlines() if not l.startswith("-----")))
    return hashlib.sha1(der).hexdigest().upper()
# En los que ya confia el navegador. Linux: los de confianza P (la de un servidor) del almacen de
# Chrome y Chromium. Mac: los de tus ajustes de confianza (los que pone add-trusted-cert)
trusted = set()
if osname == "linux":
    db = os.path.join(HOME, ".pki/nssdb")
    if os.path.isfile(os.path.join(db, "cert9.db")):
        for line in run(["certutil", "-L", "-d", "sql:" + db]).splitlines()[4:]:
            m = re.match(r"^(.*?)\s+([CcTtPpu]*,[CcTtPpu]*,[CcTtPpu]*)\s*$", line)
            if m and "P" in m.group(2).split(",")[0] and "|" not in m.group(1):
                for p in pems(run(["certutil", "-L", "-d", "sql:" + db, "-n", m.group(1), "-a"])):
                    trusted.add(sha1(p))
else:
    with tempfile.TemporaryDirectory() as t:
        run(["security", "trust-settings-export", os.path.join(t, "ajustes.plist")])
        try:
            with open(os.path.join(t, "ajustes.plist"), "rb") as f:
                trusted = {k.upper() for k in plistlib.load(f).get("trustList", {})}
        except Exception:
            pass
def own(path, bad_bits):
    # De root, fichero normal (no enlace) directamente en la carpeta de certificados del gestor
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISREG(st.st_mode) and st.st_uid == ROOT and not st.st_mode & bad_bits \
        and os.path.dirname(os.path.realpath(path)) == ssldir
try:
    sd = os.stat(ssldir)
    dir_ok = sd.st_uid == ROOT and not sd.st_mode & 0o022
except OSError:
    dir_ok = False
# Falseado: todas las lineas sin comentar de hosts que lo llevan, a este equipo (127.x o ::1)
where = {}
try:
    for line in open(os.environ.get("LVM_HOSTS_FILE") or "/etc/hosts", errors="replace"):
        w = line.split("#")[0].split()
        for n in w[1:]:
            where.setdefault(n.lower(), set()).add(w[0])
except OSError:
    pass
def faked(name):
    ips = where.get(name)
    return bool(ips) and all(ip.startswith("127.") or ip == "::1" for ip in ips)
seen, good = set(), {}
for row in os.environ.get("LVM_INFO", "").splitlines():
    f = row.split("|")
    if len(f) < 6 or f[0] != https or not re.fullmatch(r"[a-z0-9.-]+", f[2]) or not f[4]:
        continue
    dom, crt, key = f[2], f[4], f[5]
    if only and dom != only or dom in seen:
        continue
    seen.add(dom)
    alias = dom[4:] if dom.startswith("www.") else "www." + dom
    real = dom.rsplit(".", 1)[-1] not in ("local", "test", "localhost", "example", "invalid", "internal",
                                          "lan", "localdomain") and not dom.endswith(".home.arpa")
    if real and not (faked(dom) and faked(alias)):
        print("X|%s|es un dominio real y no esta falseado en hosts: con su clave (Apache la tiene en memoria) se podria suplantar la web de verdad; se confia en el solo mientras este falseado (Dominios y hosts)" % dom)
        continue
    if not dir_ok or not own(crt, 0o022) or not own(key, 0o077) or ROOT == 0 and os.access(key, os.R_OK):
        print("X|%s|no usa un certificado propio del gestor (pulsa Arreglarlos en el aviso de certificados)" % dom)
        continue
    try:
        with open(crt, errors="replace") as fh:
            p = pems(fh.read(1 << 16))
    except OSError:
        continue
    out = run(["openssl", "x509", "-noout", "-subject_hash", "-issuer_hash", "-text"], p[0].encode()) \
        if len(p) == 1 else ""
    lines = out.splitlines()
    san = re.search(r"Subject Alternative Name:.*\n\s*(.+)", out)
    names = {n.strip() for n in san.group(1).split(",")} if san else set()
    if len(lines) < 3 or lines[0].strip() != lines[1].strip() or "CA:TRUE" in out \
            or not re.search(r"Basic Constraints:.*\n\s*CA:FALSE", out) \
            or not names or not names <= {"DNS:" + dom, "DNS:" + alias}:
        print("X|%s|su certificado no es uno autofirmado solo para %s (pulsa Arreglarlos en el aviso de certificados)" % (dom, dom))
        continue
    s = sha1(p[0])
    good[dom] = s
    print("T|%s|%s|%s|%d|%d" % (dom, crt, s, s in trusted, real))
# Los nuestros que acepta el navegador y en los que ya no se puede confiar (una tienda que ya no esta
# falseada, un vhost que ya no esta...). Linux: por su nombre (lvm-instalador <dominio>) en cada
# almacen. Mac: por las copias que se guardan al confiar (<dominio>.<sha1>.crt)
if osname == "linux":
    gone = set()
    for db in [os.path.join(HOME, ".pki/nssdb"), os.path.join(HOME, "snap/chromium/current/.pki/nssdb")] \
            + glob.glob(HOME + "/.mozilla/firefox/*/") + glob.glob(HOME + "/snap/firefox/common/.mozilla/firefox/*/"):
        if not os.path.isfile(os.path.join(db, "cert9.db")):
            continue
        for line in run(["certutil", "-L", "-d", "sql:" + db]).splitlines()[4:]:
            m = re.match(r"^lvm-instalador ([a-z0-9.-]+)\s+[CcTtPpu]*,[CcTtPpu]*,[CcTtPpu]*\s*$", line)
            if m and m.group(1) not in good and (not only or m.group(1) == only):
                gone.add(m.group(1))
    for d in sorted(gone):
        print("U|" + d)
else:
    rec = os.environ.get("LVM_TRUST_DIR", "")
    for name in sorted(os.listdir(rec)) if rec and os.path.isdir(rec) else []:
        m = re.fullmatch(r"([a-z0-9.-]+)\.([0-9A-F]{40})\.crt", name)
        if m and (not only or m.group(1) == only) and good.get(m.group(1)) != m.group(2):
            print("U|%s|%s|%s|%d" % (m.group(1), os.path.join(rec, name), m.group(2), m.group(2) in trusted))
'

# confiar-certificados [dominio|--hosts|--quitar]: el navegador (Safari, Chrome) acepta sin aviso el
# certificado propio de cada proyecto https (o solo el de ese dominio). Va a tus ajustes de confianza
# (llavero de inicio de sesion), solo para webs (ssl) y solo ese certificado, no una CA: no vale para
# ninguna otra web. El Mac pide tu contraseña en cada uno. Solo los que da por buenos TRUST_PY (los de
# una tienda con dominio real, mientras este falseada en hosts), y los que ya no (U|) se quitan: para
# eso se guarda una copia de cada uno en ~/.lvm-instalador/confianza.
# --hosts (al cambiar hosts): solo quita los de las tiendas que ya no estan falseadas (y dice cuales
# se pueden confiar). --quitar: solo quita
function browser_trust() {
    local only=$1 mode=todo out t dom crt sha1 ok real n=0 failed=0 rec=$LOG_DIR/confianza
    case "$only" in
        --hosts) mode=hosts only="" ;;
        --quitar) mode=quitar only="" ;;
    esac
    if [ -n "$only" ] && ! valid_domain "$only"; then
        echo "Dominio no valido: $only"
        return 1
    fi
    out=$(LVM_INFO=$(vhosts_info) LVM_HOSTS_FILE=$HOSTS_FILE LVM_TRUST_DIR=$rec python3 -I -c "$TRUST_PY" mac "$PORT_HTTPS" "$OWN_SSL_DIR" "$only")
    [ $mode == todo ] && grep '^X|' <<< "$out" | cut -d'|' -f2- | sed 's/|/: no se confia en el: /'
    # Los que el navegador acepta y ya no se puede confiar en ellos (una tienda que ya no esta
    # falseada: el navegador va a la web de verdad, y con su clave se la podria suplantar)
    while IFS='|' read -r t dom crt sha1 ok; do
        [ "$t" == U ] || continue
        if [ "$ok" == 1 ]; then
            echo "$dom: el Mac te pide la contraseña para que el navegador deje de aceptar su certificado..."
            if ! run security remove-trusted-cert "$crt"; then
                echo "$dom: no se ha cambiado (¿has cancelado la contraseña?): el navegador aun lo acepta."
                echo "Pulsa Quitar en el aviso de la ventana."
                failed=$((failed + 1))
                continue
            fi
            run security delete-certificate -Z "$sha1" "$HOME/Library/Keychains/login.keychain-db" > /dev/null 2>&1
            echo "$dom: el navegador ya no acepta su certificado (ya no esta falseado, o su certificado o su vhost han cambiado)"
            n=$((n + 1))
        fi
        run rm -f "$crt"
    done <<< "$out"
    if [ $mode == hosts ]; then
        # Las tiendas falseadas: se confia en ellas con el boton Confiar (pide la contraseña)
        grep '^T|.*|0|1$' <<< "$out" | cut -d'|' -f2 | while read -r dom; do
            echo "$dom: para que el navegador acepte su certificado mientras este falseado, pulsa Confiar en Versiones"
        done
    elif [ $mode == todo ] && grep -q '^T|' <<< "$out"; then
        while IFS='|' read -r t dom crt sha1 ok real; do
            [ "$t" == T ] || continue
            if [ "$ok" == 1 ]; then
                echo "$dom: el navegador ya lo aceptaba"
            else
                echo "$dom: el Mac te pide la contraseña para confiar en su certificado..."
                if ! run security add-trusted-cert -r trustRoot -p ssl -k "$HOME/Library/Keychains/login.keychain-db" "$crt"; then
                    echo "$dom: no se ha cambiado (¿has cancelado la contraseña?)"
                    failed=$((failed + 1))
                    continue
                fi
                echo "$dom: el navegador ya acepta su certificado$([ "$real" == 1 ] && echo " (mientras este falseado en hosts)")"
                n=$((n + 1))
            fi
            # La copia para poder quitarlo (al dejar de falsear la tienda o si deja de ser un proyecto)
            [ -f "$rec/$dom.$sha1.crt" ] || { run mkdir -p -m 700 "$rec" && run cp "$crt" "$rec/$dom.$sha1.crt"; }
        done <<< "$out"
    elif [ $mode == todo ] && ! grep -q '^U|' <<< "$out"; then
        echo "No hay ningun proyecto https${only:+ $only} con un certificado propio en el que confiar."
        [ -z "$only" ] || return 1
    fi
    rm -f "$LOG_DIR/certificados"
    [ $failed -eq 0 ] || return 1
    [ $n -gt 0 ] || return 0
    echo
    echo "Si Chrome estaba abierto y aun avisa en algun proyecto (o aun acepta uno que ya no esta falseado),"
    echo "cierralo del todo y vuelve a abrirlo."
    return 0
}

# Alias del dominio: www.dominio, o el dominio sin www si ya lo lleva
function domain_alias() {
    if [[ "$1" == www.* ]]; then echo "${1#www.}"; else echo "www.$1"; fi
}

# Dominio de una tienda PrestaShop. Primero el de su base (tabla shop_url, tienda principal), que es
# al que redirige; si la base no se puede leer (MariaDB parado o root con contraseña), el ServerName
# del vhost que ya apunte a la carpeta.
function ps_domain() {
    local folder=$1 config db prefix domain
    config=$(ps_config "$folder")
    db=${config%%|*} prefix=${config#*|}
    if [ -n "$db" ] && [[ "$db$prefix" =~ ^[A-Za-z0-9_-]+$ ]] && [ -x "$DB_CLIENT" ] \
            && db_base_table root "${MYSQL_PWD:-}" "$db" "${prefix}shop_url"; then
        # Si MariaDB se acaba de arrancar (cambio de version), se le dan unos segundos
        for _ in 1 2 3 4 5 6; do
            domain=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT domain FROM \`$db\`.\`${prefix}shop_url\` ORDER BY main DESC, active DESC, id_shop_url LIMIT 1" < /dev/null 2>&1) && break
            [[ "$domain" == *"Can't connect"* ]] && [ "$DRY" -eq 0 ] || break
            sleep 1
        done
        domain=$(tr 'A-Z' 'a-z' <<< "${domain%%:*}")
        valid_domain "$domain" && echo "$domain" && return 0
    fi
    domain=$(vhosts_info | awk -F'|' -v f="$folder" -v l="$(project_link)" '$2 == f && $3 != l { print $3; exit }')
    [ -n "$domain" ] && echo "$domain"
}

# ¿Hay ya un vhost con ese dominio que apunte a la carpeta?
function vhost_points_to() {
    vhosts_info | awk -F'|' -v d="$1" -v f="$2" '$3 == d && $2 == f { found = 1 } END { exit !found }'
}

# ¿Se parece el dominio a la carpeta? Su nombre registrable (lo de antes de la terminacion:
# mitienda en www.mitienda.com, ejemplo en tienda.ejemplo.com, cliente en
# cliente.com.es), de 4 letras o mas, va en el nombre de la carpeta sin sus palabras genericas
# (dob, prestashop, wordpress...): asi prestashop.com no vale para dob-prestashop-x
function domain_fits_folder() {
    local domain=${1#www.} folder label w n parts
    folder=$(tr 'A-Z' 'a-z' <<< "$2")
    for w in dob prestashop wordpress tienda shop html php web wp ps; do folder=${folder//$w/}; done
    folder=$(tr -d '._-' <<< "$folder")
    IFS=. read -r -a parts <<< "$(tr 'A-Z' 'a-z' <<< "$domain")"
    n=${#parts[@]}
    (( n >= 2 )) || return 1
    label=${parts[n-2]}
    if (( n >= 3 )) && [[ "$label" =~ ^(com|co|org|net|gob|edu|ac|nom)$ ]]; then label=${parts[n-3]}; fi
    label=$(tr -d '_-' <<< "$label")
    [ ${#label} -ge 4 ] && [[ "$folder" == *"$label"* ]]
}

# ¿Es <tabla> de <base> una tabla de verdad (no una vista, que podria ejecutar funciones del volcado
# con los permisos de quien la lee)? db_base_table <usuario> <contraseña> <base> <tabla>
function db_base_table() {
    local n
    if [ -n "$2" ]; then
        n=$(MYSQL_PWD=$2 "${DB_SAFE[@]}" "$DB_CLIENT" -u"$1" -N -e "SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA='$3' AND TABLE_NAME='$4' AND TABLE_TYPE='BASE TABLE'" < /dev/null 2> /dev/null)
    else
        n=$(env -u MYSQL_PWD "${DB_SAFE[@]}" "$DB_CLIENT" -u"$1" -N -e "SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA='$3' AND TABLE_NAME='$4' AND TABLE_TYPE='BASE TABLE'" < /dev/null 2> /dev/null)
    fi
    [ "$n" == 1 ]
}

# Correo del ServerAdmin de los vhosts que se crean: el de git del usuario que usa la app
# (user.email de su ~/.gitconfig) o usuario@localhost
function server_admin() {
    local user=${SUDO_USER:-$USER} home mail
    home=$(dscl . -read "/Users/$user" NFSHomeDirectory 2> /dev/null | awk '{ print $2 }')
    mail=$(HOME=${home:-$HOME} git config --global user.email 2> /dev/null)
    # (va como root en los vhosts: sin \ al final, que uniria la linea con la siguiente, ni comillas)
    [[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || user=webmaster
    [[ "$mail" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]] && echo "$mail" || echo "$user@localhost"
}

# Comprueba que el dominio tiene vhost http y https apuntando a la carpeta y certificado. Lo que
# falte se crea como en el manual: certificado <dominio>-selfsigned en XAMPP-compartido/ssl y bloques al final
# de VHOSTS_FILE (se guarda copia en ~/lvm-copias). Deja PS_RELOAD=1 si ha cambiado algo.
function ps_vhost() {
    local folder=$1 domain=$2 alias info http https crt key other s="" block="" openssl=/usr/bin/openssl
    # El dominio va en el vhost, en /etc/hosts y en el nombre del certificado: solo uno valido
    valid_domain "$domain" || { echo "Dominio no valido: $domain"; return 1; }
    alias=$(domain_alias "$domain")
    info=$(vhosts_info)
    http=$(awk -F'|' -v p="$PORT_HTTP" -v d="$domain" '$1 == p && $3 == d' <<< "$info" | head -1)
    https=$(awk -F'|' -v p="$PORT_HTTPS" -v d="$domain" '$1 == p && $3 == d' <<< "$info" | head -1)

    other=$(printf '%s\n%s\n' "$http" "$https" | awk -F'|' -v f="$folder" '$0 != "" && $2 != f { print $2; exit }')
    if [ -n "$other" ]; then
        echo "Aviso: el vhost de $domain apunta a $HTDOCS_DIR/$other, no a $folder. No se cambia:"
        echo "revisalo en Editar vhosts si no es lo que quieres."
    fi

    crt=$(cut -d'|' -f5 <<< "$https") key=$(cut -d'|' -f6 <<< "$https")
    if [ -z "$https" ]; then
        crt="$SSL_CERTS_DIR/$domain-selfsigned.crt" key="$SSL_KEYS_DIR/$domain-selfsigned.key"
    fi
    if [ -n "$crt" ] && [ -n "$key" ] && [ ! -f "$crt" ]; then
        echo "Creando el certificado autofirmado de $domain ($crt)..."
        make_selfsigned "$domain" "$alias" "$crt" "$key" || return 1
        PS_RELOAD=1
    fi

    if [ -z "$http" ]; then
        block+="
<VirtualHost *:$PORT_HTTP>
    ServerAdmin $(server_admin)
    DocumentRoot \"$LINK/xamppfiles/htdocs/$folder\"
    ServerName $domain
    ServerAlias $alias
    ErrorLog \"logs/$domain-error_log\"
</VirtualHost>
"
    fi
    if [ -z "$https" ]; then
        block+="
<VirtualHost *:$PORT_HTTPS>
    ServerAdmin $(server_admin)
    DocumentRoot \"$LINK/xamppfiles/htdocs/$folder\"
    ServerName $domain
    ServerAlias $alias

    SSLEngine on
    SSLCertificateFile $crt
    SSLCertificateKeyFile $key
</VirtualHost>
"
    fi
    [ -z "$block" ] && return 0

    block="

######################### URL $(tr 'a-z' 'A-Z' <<< "$domain") (lvm-instalador) #########################
$block"
    echo "Añadiendo el vhost de $domain ($([ -z "$http" ] && echo -n "http ")$([ -z "$https" ] && echo -n "https")) a $VHOSTS_FILE..."
    s=""
    [ -w "$VHOSTS_FILE" ] || s=$SUDO
    if [ -f "$VHOSTS_FILE" ]; then
        run mkdir -p -m 700 "$HOME/lvm-copias"
        run cp "$VHOSTS_FILE" "$HOME/lvm-copias/httpd-vhosts.conf-$(date +%Y%m%d-%H%M%S)" || return 1
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] añadir a $VHOSTS_FILE:$block"
    else
        # (como root, solo en el fichero de XAMPP-compartido y sin enlaces: ver vhosts_path_ok)
        if [ -n "$s" ] && ! vhosts_path_ok; then
            echo "No se añade el vhost: $VHOSTS_FILE tiene que ser un fichero normal de $COMMON (sin enlaces)."
            return 1
        fi
        printf '%s' "$block" | $s tee -a "$VHOSTS_FILE" > /dev/null || return 1
    fi
    PS_RELOAD=1
}

# Falsea dominios en /etc/hosts (en el Mac, con una linea 127.0.0.1 y otra ::1: si solo hubiera la
# de IPv4, macOS podria buscar la direccion IPv6 del dominio en internet y abrir la web real). Modo carga: falsea los indicados (puede no haber ninguno) y deja de
# falsear el resto de dominios de los vhosts. Modo si/no: solo falsea o deja de falsear uno.
# Solo toca lineas 127.0.0.1/::1 cuyos nombres sean todos dominios de vhosts de proyectos (nunca
# localhost, web.local ni el nombre del equipo): las comenta o les quita el # (y añade la linea
# si no existia). Se escribe con edit_hosts --aplicar (copia del anterior en ~/lvm-copias).
function hosts_fake() {
    local mode=$1 copy rc
    shift
    copy=$(mktemp "${TMPDIR:-/tmp}/lvm-hosts.XXXXXX") || return 1
    LVM_INFO=$(vhosts_info) LVM_LOCAL_OFF="$(cat "$LOCAL_OFF_FILE" 2> /dev/null) $LOCAL_OFF_DRY" \
        python3 -I - "$HOSTS_FILE" "$copy" "$mode" "$PROJECT_VHOST $(project_link)" "$@" <<'EOF'
import os, re, sys
src, dst, mode, links = sys.argv[1:5]
wanted = [d.lower() for d in sys.argv[5:]]
skip = {"localhost"}
for l in links.lower().split():
    skip |= {l, "www." + l}
managed = set()
for row in os.environ.get("LVM_INFO", "").splitlines():
    f = row.split("|")
    if len(f) >= 4:
        managed |= {n.lower() for n in [f[2]] + f[3].split() if n}
managed -= skip
# Los .local no existen fuera: se quedan siempre en hosts (al cargar otro proyecto no se comentan) y
# se añaden si les falta la linea. Sin ella, el equipo los pregunta a la red (mDNS) y cualquiera de
# la misma wifi podria contestar con su IP y servir su web con ese nombre. Salvo los que se han
# apagado a mano en la pestaña Hosts (LOCAL_OFF_FILE): esos se tratan como un dominio mas
off = {n.lower() for n in os.environ.get("LVM_LOCAL_OFF", "").split()}
always = {n.lower() for n in managed if n.lower().endswith(".local")} - off
managed -= always
target = set()
for d in wanted:
    target |= {d, d[4:] if d.startswith("www.") else "www." + d}
# localhost y el vhost de los proyectos (web.local) no se tocan nunca
wanted = [d for d in wanted if d not in skip]
target -= skip
# (un .local no se apaga: no hay ninguna web «real» a la que devolverlo, y sin su linea se
# preguntaria a la red)
if mode == "no":
    managed |= target - always
lines = open(src).read().splitlines()
rx = re.compile(r"^(\s*)(#+\s*)?(127\.0\.0\.1|::1)(\s+)(.*?)\s*$")
IPS = ["127.0.0.1", "::1"]
dones, changes, out = {ip: set() for ip in IPS}, [], []
for line in lines:
    m = rx.match(line)
    names = m.group(5).split("#")[0].split() if m else []
    lnames = {n.lower() for n in names}
    # (una linea con un .local y un dominio de verdad, de un vhost con los dos, tambien es nuestra)
    ours = bool(names) and lnames <= (managed | always | target) and bool(lnames - always)
    if not ours:
        out.append(line)
        continue
    active = not m.group(2)
    done = dones[m.group(3)]
    if lnames & target:
        # Se falsea (sin quitar el # a una segunda linea repetida) o se deja de falsear
        on = mode != "no" and (active or not lnames <= done)
    else:
        # Al cargar un proyecto, el resto de dominios vuelve a la web real
        on = active and mode != "cargar"
    if on and not active:
        line = m.group(1) + m.group(3) + m.group(4) + m.group(5)
        changes.append("Falseado en %s (%s): %s" % (src, m.group(3), " ".join(names)))
    elif not on and active:
        line = m.group(1) + "#" + m.group(3) + m.group(4) + m.group(5)
        # Los .local de esa linea no se comentan: se quedan activos en otra
        keep = [n for n in names if n.lower() in always]
        if keep:
            line = m.group(1) + "#" + m.group(3) + m.group(4) + " ".join(n for n in names if n.lower() not in always)
            out.append(m.group(1) + m.group(3) + m.group(4) + " ".join(keep))
        if all(n.lower().endswith(".local") for n in names):
            changes.append("Apagado en %s (%s): %s" % (src, m.group(3), " ".join(names)))
        else:
            changes.append("Ya no esta falseado (%s, lleva a la web real): %s" % (m.group(3), " ".join(names)))
    if on:
        done |= lnames
    out.append(line)
active_names = {ip: set() for ip in IPS}
off_names = set()
for l in out:
    mm = rx.match(l)
    if mm and not mm.group(2):
        active_names[mm.group(3)] |= {n.lower() for n in mm.group(5).split("#")[0].split()}
    elif mm:
        off_names |= {n.lower() for n in mm.group(5).split("#")[0].split()}
# (tambien los que esten comentados: se vuelven a añadir)
for ip in IPS:
    for d in sorted(always - active_names[ip]):
        last = max([i for i, l in enumerate(out) if rx.match(l)] or [len(out) - 1])
        out.insert(last + 1, "%s %s" % (ip, d))
        changes.append("En %s (%s), para que no se pregunte a la red: %s" % (src, ip, d))
if mode in ("cargar", "si"):
    for d in wanted:
        for ip in IPS:
            if d in dones[ip]:
                continue
            alias = d[4:] if d.startswith("www.") else "www." + d
            new = "%s %s %s" % (ip, d, alias)
            last = max([i for i, l in enumerate(out) if rx.match(l)] or [len(out) - 1])
            out.insert(last + 1, new)
            dones[ip] |= {d, alias}
            changes.append("Falseado en %s (%s): %s %s" % (src, ip, d, alias))
open(dst, "w").write("\n".join(out) + "\n")
for c in changes:
    print(c)
EOF
    rc=$?
    if [ $rc -ne 0 ]; then
        rm -f "$copy"
        echo "No se ha podido preparar el nuevo $HOSTS_FILE"
        return 1
    fi
    if ! cmp -s "$copy" "$HOSTS_FILE"; then
        edit_hosts --aplicar "$copy" || { rm -f "$copy"; return 1; }
    fi
    rm -f "$copy"
}

# hosts-enlace: el vhost de los proyectos (web.local) pasa a 127.0.0.1 en hosts, que es donde escucha
# Apache. Se quita de las lineas que lo llevaban a otra direccion (la del nombre del equipo se queda
# con sus otros nombres) y se añade su linea. Con copia del anterior en ~/lvm-copias (edit_hosts)
function hosts_fix_link() {
    local link copy
    link=$(project_link)
    link=${link:-$PROJECT_VHOST}
    valid_domain "$link" || { echo "No hay vhost de los proyectos"; return 1; }
    copy=$(mktemp "${TMPDIR:-/tmp}/lvm-hosts.XXXXXX") || return 1
    if ! python3 -I - "$HOSTS_FILE" "$copy" "$link" <<'EOF'
import re, sys
src, dst, name = sys.argv[1], sys.argv[2], sys.argv[3].lower()
out, changes, ok, ok6 = [], [], False, False
for line in open(src, errors="surrogateescape").read().splitlines():
    body, sep, comment = line.partition("#")
    w = body.split()
    if len(w) >= 2 and name in [x.lower() for x in w[1:]]:
        if w[0] == "127.0.0.1":
            ok = True
        elif w[0] == "::1":
            ok6 = True
        else:
            rest = [x for x in w[1:] if x.lower() != name]
            changes.append("%s ya no lleva a %s" % (name, w[0]))
            if rest:
                line = " ".join([w[0]] + rest) + ((" " + sep + comment) if sep else "")
            else:
                line = "# (lvm-instalador: %s pasa a 127.0.0.1) %s" % (name, line)
    out.append(line)
if not ok:
    last = max([i for i, l in enumerate(out) if re.match(r"\s*127\.0\.0\.1\s", l)] or [len(out) - 1])
    out.insert(last + 1, "127.0.0.1 %s" % name)
    changes.append("%s lleva a este Mac (127.0.0.1)" % name)
if not ok6:
    out.append("::1 %s" % name)
    changes.append("%s lleva a este Mac (::1)" % name)
open(dst, "w", errors="surrogateescape").write("\n".join(out) + "\n")
for c in changes:
    print(c)
EOF
    then
        rm -f "$copy"
        return 1
    fi
    if cmp -s "$copy" "$HOSTS_FILE"; then
        echo "$link ya lleva a este Mac (127.0.0.1)"
    else
        edit_hosts --aplicar "$copy" || { rm -f "$copy"; return 1; }
    fi
    rm -f "$copy"
}

# hosts-falsear <dominio> si|no: el interruptor de la pestaña Hosts
function hosts_fake_one() {
    local domain=$(tr 'A-Z' 'a-z' <<< "$1") state=$2
    if ! valid_domain "$domain" || [[ "$state" != si && "$state" != no ]]; then
        echo "Uso: lvm-instalador hosts-falsear <dominio> si|no"

        return 1
    fi
    local link
    for link in localhost "$PROJECT_VHOST" $(project_link); do
        if [ "$domain" == "$link" ] || [ "$domain" == "www.$link" ]; then
            echo "$domain no se falsea ni se deja de falsear desde aqui: es el de los proyectos o el del equipo"

            return 1
        fi
    done
    if ! vhosts_info | awk -F'|' -v d="$domain" '$3 == d || index(" " $4 " ", " " d " ") { f = 1 } END { exit !f }'; then
        echo "$domain no es el dominio de ningun vhost de $VHOSTS_FILE"

        return 1
    fi
    # La contraseña antes de cambiar nada: cancelarla deja el dominio como estaba
    sudo_first || return 1
    # Un .local se queda siempre en hosts (sin su linea, el equipo lo preguntaria a la red y
    # cualquiera de la misma wifi podria contestar), salvo que se apague aqui: se recuerda en
    # LOCAL_OFF_FILE, con su www., y al encenderlo se olvida
    if [[ "$domain" == *.local ]]; then
        local base=${domain#www.}
        local_off "$state" "$base" "www.$base" || return 1
        if ! hosts_fake "$state" "$domain"; then
            local_off "$([ "$state" == no ] && echo si || echo no)" "$base" "www.$base"

            return 1
        fi
        if [ "$state" == si ]; then
            echo "$domain encendido: lleva a este Mac (127.0.0.1 y ::1) y se vuelve a mantener en $HOSTS_FILE"
        else
            echo "$domain apagado: sus lineas de $HOSTS_FILE quedan comentadas y no se vuelven a añadir."
            echo "Mientras este apagado, el Mac lo pregunta a la red (cualquiera de la misma wifi podria contestar)."
        fi

        return 0
    fi
    hosts_fake "$state" "$domain" || return 1
    if [ "$state" == si ]; then
        echo "$domain falseado: lleva a este equipo (127.0.0.1 y ::1)"
    else
        echo "$domain ya no esta falseado: lleva a la web real"
    fi
}

# media-produccion <dominio .local> <dominio de produccion>|quitar: lo que falte en local de
# wp-content/uploads o img (imagenes, videos y pdf; uploads e img no van en git) se pide a la web
# de produccion con una redireccion 302, en los vhosts de ese dominio (http y https). Solo en los
# .local: con el dominio real falseado, la redireccion volveria a este equipo. Y el de produccion no
# puede ser un .local: si se falsea, la peticion cae en su propio vhost, sin la regla (404, sin bucle)
# Solo GET y HEAD, y solo esas extensiones: un .php de uploads no se manda a ningun sitio
MEDIA_EXT="jpe?g|png|gif|webp|avif|svg|ico|bmp|mp4|webm|pdf"
function media_proxy() {
    local domain=$(tr 'A-Z' 'a-z' <<< "$1") prod=$(tr 'A-Z' 'a-z' <<< "$2") copy rc
    if [ -z "$domain" ] || [ -z "$prod" ]; then
        echo "Uso: lvm-instalador media-produccion <dominio .local> <dominio de produccion>|quitar"

        return 1
    fi
    domain=${domain#www.}
    if ! valid_domain "$domain" || [[ "$domain" != *.local ]]; then
        echo "$domain no es un dominio .local: el proxy de imagenes solo va en los vhosts .local"
        echo "(con el dominio real falseado, la redireccion volveria a este equipo)"

        return 1
    fi
    if [ "$prod" != quitar ]; then
        prod=${prod#https://}; prod=${prod#http://}; prod=${prod%/}
        if ! valid_domain "$prod" || [[ "$prod" == *.local || "$prod" == localhost || "$prod" == *.localhost ]]; then
            echo "El dominio de produccion no es valido: $prod (solo el dominio, como ejemplo.com)"

            return 1
        fi
    fi
    if ! vhosts_info | awk -F'|' -v d="$domain" '$3 == d || index(" " $4 " ", " " d " ") { f = 1 } END { exit !f }'; then
        echo "$domain no es el dominio de ningun vhost de $VHOSTS_FILE"

        return 1
    fi
    mkdir -p -m 700 "$LOG_DIR" || return 1
    copy=$(mktemp "$LOG_DIR/vhosts-media-XXXXXX") || return 1
    python3 -I - "$(realpath_f "$ACTIVE_VHOSTS")" "$copy" "$domain" "$prod" "$MEDIA_EXT" << 'EOF'
import re, sys
src, dst, domain, prod, ext = sys.argv[1:6]
lines = open(src, encoding="utf-8", errors="surrogateescape", newline="").read().split("\n")
rule = ["    # nexum-media %s: lo que falte aqui de wp-content/uploads o img se pide a produccion (no se edita a mano: lvm-instalador media-produccion)" % prod,
        "    <IfModule rewrite_module>",
        "        RewriteEngine On",
        "        RewriteCond %{REQUEST_METHOD} ^(GET|HEAD)$",
        "        RewriteCond %{DOCUMENT_ROOT}%{REQUEST_URI} !-f",
        "        RewriteRule ^/((wp-content/uploads|img)/.+\\.(%s))$ https://%s/$1 [NC,R=302,L]" % (ext, prod),
        "    </IfModule>",
        "    # /nexum-media"]
found = 0
def fix(block):
    global found
    names = set()
    for l in block:
        w = l.split("#", 1)[0].split()
        if len(w) >= 2 and w[0].lower() in ("servername", "serveralias"):
            names |= {n.lower().split(":")[0] for n in w[1:]}
    if domain not in names and "www." + domain not in names:
        return block
    found += 1
    # (la regla anterior, si la habia, se quita: se pone la nueva o ninguna)
    out, skip = [], False
    for l in block:
        s = l.strip()
        if s.startswith("# nexum-media "):
            skip = True
        elif skip and s == "# /nexum-media":
            skip = False
        elif not skip:
            out.append(l)
    if prod != "quitar":
        out[-1:-1] = rule
    return out
out, block = [], None
for line in lines:
    if block is None:
        if re.match(r"^\s*<VirtualHost\b", line, re.I):
            block = [line]
        else:
            out.append(line)
        continue
    block.append(line)
    if re.match(r"^\s*</VirtualHost>", line, re.I):
        out += fix(block)
        block = None
if block:
    out += block
if not found:
    sys.exit(2)
with open(dst, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write("\n".join(out))
sys.exit(0 if out != lines else 3)
EOF
    rc=$?
    if [ $rc -eq 3 ]; then
        rm -f "$copy"
        [ "$prod" == quitar ] && echo "$domain no pedia nada a produccion" || echo "$domain ya pide a $prod lo que falte"

        return 0
    fi
    if [ $rc -ne 0 ]; then
        rm -f "$copy"
        echo "No se encuentra el vhost de $domain en $(realpath_f "$ACTIVE_VHOSTS")"

        return 1
    fi
    if [ "$prod" == quitar ]; then
        echo "$domain: lo que falte de uploads e img ya no se pide a produccion"
    else
        echo "$domain: lo que falte de wp-content/uploads o img se pide a https://$prod"
    fi
    edit_vhosts --aplicar "$copy" || { rm -f "$copy"; return 1; }
    rm -f "$copy"
}

# Dominio de produccion de cada WordPress para sus imagenes (media-proyecto): carpeta|dominio. Se
# aplica al vhost de los proyectos (web.local) mientras ese proyecto este cargado (media_sync)
MEDIA_PROJECTS_FILE="$HOME/.lvm-instalador/media-produccion"
function media_saved() {
    awk -F'|' -v f="$1" '$1 == f { d = $2 } END { if (d != "") print d }' "$MEDIA_PROJECTS_FILE" 2> /dev/null
}

# media-proyecto <carpeta> <dominio de produccion>|quitar: lo que le falte a un WordPress de
# wp-content/uploads se pide a su web real mientras este cargado (por web.local, que es un .local:
# sin bucles). Las tiendas PrestaShop se ven con su dominio real falseado: para ellas, ps-imagenes
function media_project() {
    local folder=${1%/} prod=$(tr 'A-Z' 'a-z' <<< "$2") rest
    if [ -z "$folder" ] || [ -z "$prod" ]; then
        echo "Uso: lvm-instalador media-proyecto <carpeta> <dominio de produccion>|quitar"

        return 1
    fi
    valid_project "$folder" || return 1
    if is_prestashop "$folder"; then
        echo "$folder es una tienda PrestaShop: se ve con su dominio real falseado y una redireccion volveria"
        echo "a este equipo. Descarga las imagenes que faltan: lvm-instalador ps-imagenes $folder"

        return 1
    fi
    if [ "$prod" != quitar ]; then
        prod=${prod#https://}; prod=${prod#http://}; prod=${prod%/}
        if ! valid_domain "$prod" || [[ "$prod" == *.local || "$prod" == localhost || "$prod" == *.localhost ]]; then
            echo "El dominio de produccion no es valido: $prod (solo el dominio, como ejemplo.com)"

            return 1
        fi
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $folder: $([ "$prod" == quitar ] && echo "se olvida su dominio de produccion" || echo "imagenes de $prod") en $MEDIA_PROJECTS_FILE"
    else
        mkdir -p -m 700 "$(dirname "$MEDIA_PROJECTS_FILE")" || return 1
        rest=$(awk -F'|' -v f="$folder" '$1 != f' "$MEDIA_PROJECTS_FILE" 2> /dev/null)
        [ "$prod" != quitar ] && rest+=$'\n'"$folder|$prod"
        ( umask 077; sed '/^$/d' <<< "$rest" > "$MEDIA_PROJECTS_FILE" ) || return 1
    fi
    if [ "$prod" == quitar ]; then
        echo "$folder ya no pide a produccion las imagenes que le faltan"
    else
        echo "$folder pide a https://$prod las imagenes que le falten en wp-content/uploads (mientras este cargado"
        echo "y, si esta en el Apache de Docker, tambien alli)"
    fi
    media_sync
    # (en el Apache de Docker, en sus vhosts: se rehacen y se recargan)
    local p
    for p in $(docker_web_projects 2> /dev/null); do
        if [ "$(docker_conf "$p" CARPETA)" == "$folder" ] && [ "$DRY" -eq 0 ]; then
            docker_web_reload || echo "Aviso: el Apache de Docker no ha recargado su configuracion"
            break
        fi
    done
}

# Regla de imagenes del vhost de los proyectos (web.local) segun el proyecto cargado: la de su
# dominio de produccion (media-proyecto) si es un WordPress que lo tiene, si no ninguna. Solo cambia
# los vhosts si hace falta
function media_sync() {
    local link folder name want="" now
    link=$(project_link) || return 0
    folder=$(readlink "$HTDOCS_DIR/$link" 2> /dev/null | sed 's:/*$::')
    name=$(vhosts_info | awk -F'|' -v l="$link" '$2 == l { print $3; exit }')
    [[ "$name" == *.local ]] || return 0
    if [ -n "$folder" ] && [ "$folder" != "$EMPTY_PROJECT" ] && [ -d "$HTDOCS_DIR/$folder" ] && ! is_prestashop "$folder"; then
        want=$(media_saved "$folder")
    fi
    now=$(awk -v n="$name" '
        /^[ \t]*<VirtualHost/ { hit = 0 }
        tolower($1) == "servername" || tolower($1) == "serveralias" { for (i = 2; i <= NF; i++) if (tolower($i) == n) hit = 1 }
        hit && $1 == "#" && $2 == "nexum-media" { sub(/:$/, "", $3); print $3; exit }' "$(realpath_f "$ACTIVE_VHOSTS")" 2> /dev/null)
    [ "$want" == "$now" ] && return 0
    media_proxy "$name" "${want:-quitar}"
}

# Para la ventana: G|dominio guardado de un WordPress (media-proyecto) y D|el de su base (home o
# siteurl de la tabla options, que el gestor no cambia: el local va en WP_HOME de wp-config.php)
function gui_wp_prod() {
    local folder=$1 cfg db prefix url
    valid_project "$folder" > /dev/null || return 1
    echo "G|$(media_saved "$folder")"
    cfg=$(wp_config_read "$HTDOCS_DIR/$folder/wp-config.php") || return 0
    db=$(sed -n 1p <<< "$cfg") prefix=$(sed -n 4p <<< "$cfg")
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] && [[ "$prefix" =~ ^[A-Za-z0-9_]*$ ]] || return 0
    if ! { [ -x "$DB_CLIENT" ] && db_base_table root "${MYSQL_PWD:-}" "$db" "${prefix}options"; }; then
        # (sin ella en la version activa: la de su proyecto del Apache de Docker, si lo hay)
        local p
        for p in $(docker_web_projects 2> /dev/null); do
            [ "$(docker_conf "$p" CARPETA)" == "$folder" ] || continue
            docker_ready || return 0
            url=$(docker_maria_sql "$(docker_conf "$p" MARIADB)" -N -e "SELECT option_value FROM \`$(docker_conf "$p" BBDD)\`.\`${prefix}options\`
                WHERE option_name IN ('home', 'siteurl') ORDER BY option_name = 'home' DESC LIMIT 1" < /dev/null 2> /dev/null | tr -d '\r')
            url=$(tr 'A-Z' 'a-z' <<< "$url" | sed -E 's|^https?://||; s|[/:?#].*$||')
            valid_domain "$url" && [[ "$url" != *.local && "$url" != *.test && "$url" != localhost && "$url" != *.localhost ]] && echo "D|$url"
        done
        return 0
    fi
    url=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT option_value FROM \`$db\`.\`${prefix}options\`
        WHERE option_name IN ('home', 'siteurl') ORDER BY option_name = 'home' DESC LIMIT 1" < /dev/null 2> /dev/null)
    url=$(tr 'A-Z' 'a-z' <<< "$url" | sed -E 's|^https?://||; s|[/:?#].*$||')
    valid_domain "$url" && [[ "$url" != *.local && "$url" != localhost && "$url" != *.localhost ]] && echo "D|$url"
    return 0
}

# ps-imagenes <carpeta>: descarga de la web real las imagenes de una tienda PrestaShop que faltan en
# img (productos, categorias y marcas, con sus miniaturas; la lista sale de su base). La tienda se ve
# con su dominio real falseado, asi que una redireccion no sirve: se descargan por https resolviendo
# el dominio con DNS cifrado (PS_IMAGES_DOH, sin /etc/hosts) y comprobando su certificado de
# verdad. Cada fichero va a una carpeta temporal y solo pasa a img si ha llegado entero (200); sin
# seguir redirecciones y como mucho 30 MB por fichero. Lo que ya esta en local no se toca
PS_IMAGES_DOH="https://cloudflare-dns.com/dns-query"
function ps_images() {
    local folder=${1%/} domain=$2 config db prefix t list total web="" maria="" p
    if [ -z "$folder" ]; then
        echo "Uso: lvm-instalador ps-imagenes <carpeta> [dominio de produccion]"

        return 1
    fi
    valid_project "$folder" || return 1
    is_prestashop "$folder" || { echo "$folder no es una tienda PrestaShop"; return 1; }
    command -v curl > /dev/null || { echo "Hace falta curl: sudo apt install curl"; return 1; }
    config=$(ps_config "$folder")
    db=${config%%|*} prefix=${config#*|}
    [ -n "$db" ] && [[ "$db$prefix" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "No se puede leer la BBDD de $folder (su parameters.php o settings.inc.php)"; return 1; }
    # La BBDD con la lista de imagenes: la de la version activa o, si no esta alli, la de su proyecto del
    # Apache de Docker (las imagenes van a su carpeta img, la misma con LAMPP y con Docker)
    for p in $(docker_web_projects 2> /dev/null); do
        [ "$(docker_conf "$p" CARPETA)" == "$folder" ] && web=$p
    done
    if { db_connect > /dev/null 2>&1 && db_exists "$db"; } || [ -z "$web" ]; then
        db_connect || return $?
        if ! db_exists "$db"; then
            echo "La BBDD de $folder ($db) no esta en lampp-$DB_FOLDER, la version activa: carga el proyecto"
            echo "en su version (o importa su BBDD en esta) y vuelve a intentarlo"

            return 1
        fi
        [ -n "$domain" ] || domain=$(ps_domain "$folder")
    else
        db=$(docker_conf "$web" BBDD) maria=$(docker_conf "$web" MARIADB)
        db_valid_name "$db" > /dev/null || { echo "$web no tiene una BBDD valida en su proyecto.conf"; return 1; }
        docker_ready || { echo "Docker no esta en marcha: arrancalo y vuelve a intentarlo"; return 1; }
        docker_maria_up "$maria" > /dev/null || { echo "La MariaDB $maria de Docker no responde"; return 1; }
        echo "Con la BBDD de la tienda en Docker ($db, MariaDB $maria)"
        [ -n "$domain" ] || domain=$(docker_conf "$web" PRODUCCION)
    fi
    domain=$(tr 'A-Z' 'a-z' <<< "$domain")
    domain=${domain#https://} domain=${domain#http://} domain=${domain%/}
    if ! valid_domain "$domain" || [[ "$domain" == *.local || "$domain" == *.test || "$domain" == localhost || "$domain" == *.localhost ]]; then
        echo "No se sabe el dominio de produccion de $folder: ${domain:-ninguno}. Dilo tu:"
        echo "lvm-instalador ps-imagenes $folder <dominio de produccion>"

        return 1
    fi
    # (en Docker, preguntas a su MariaDB comun; las dos, solo tablas de verdad)
    tbl() {
        if [ -n "$maria" ]; then
            [ "$(docker_maria_sql "$maria" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$db' AND table_name = '$1' AND table_type = 'BASE TABLE'" < /dev/null 2> /dev/null | tr -d '\r')" == 1 ]
        else
            db_base_table root "${MYSQL_PWD:-}" "$db" "$1"
        fi
    }
    # (solo tablas de verdad: una vista del volcado ejecutaria sus funciones como root)
    for t in image image_type; do
        tbl "$prefix$t" || { echo "La BBDD $db no tiene la tabla $prefix$t"; return 1; }
    done
    local sql=(db_root_sql -N -B)
    [ -n "$maria" ] && sql=(docker_maria_sql "$maria" -N -B)
    list=$( {
        "${sql[@]}" -e "SELECT 'I', id_image FROM \`$db\`.\`${prefix}image\`" < /dev/null
        "${sql[@]}" -e "SELECT 'T', name, products, categories, manufacturers FROM \`$db\`.\`${prefix}image_type\`" < /dev/null
        tbl "${prefix}category" \
            && "${sql[@]}" -e "SELECT 'C', id_category FROM \`$db\`.\`${prefix}category\` WHERE id_category > 2" < /dev/null
        tbl "${prefix}manufacturer" \
            && "${sql[@]}" -e "SELECT 'M', id_manufacturer FROM \`$db\`.\`${prefix}manufacturer\`" < /dev/null
    } 2> /dev/null | python3 -I -c '
import os, re, sys
root = sys.argv[1]
ids, types = {"I": [], "C": [], "M": []}, {"I": [], "C": [], "M": []}
for line in sys.stdin:
    f = line.rstrip("\n").split("\t")
    if f[0] in ids and len(f) == 2 and f[1].isdigit():
        ids[f[0]].append(int(f[1]))
    elif f[0] == "T" and len(f) == 5 and re.match(r"^[A-Za-z0-9_-]{1,64}$", f[1]):
        for k, col in (("I", 2), ("C", 3), ("M", 4)):
            if f[col] == "1":
                types[k].append(f[1])
for k, base in (("I", "img/p"), ("C", "img/c"), ("M", "img/m")):
    for i in sorted(set(ids[k])):
        d = base + "/" + "/".join(str(i)) if k == "I" else base
        for t in [""] + types[k]:
            rel = "%s/%d%s.jpg" % (d, i, "-" + t if t else "")
            if not os.path.isfile(os.path.join(root, rel)):
                print(rel)
' "$HTDOCS_DIR/$folder")
    total=$(grep -c . <<< "$list")
    if [ "$total" -eq 0 ]; then
        echo "A $folder no le falta ninguna imagen de productos, categorias ni marcas"

        return 0
    fi
    echo "A $folder le faltan $total imagenes: se descargan de https://$domain"
    echo "($domain se resuelve con DNS cifrado, sin /etc/hosts, y se comprueba su certificado)"
    if [ "$DRY" -eq 1 ]; then
        head -3 <<< "$list" | sed 's/^/  [simulacion] /'

        return 0
    fi
    mkdir -p -m 700 "$LOG_DIR" || return 1
    local file rc
    file=$(mktemp "$LOG_DIR/ps-imagenes-lista-XXXXXX") || return 1
    printf '%s\n' "$list" > "$file"
    python3 -I - "$HTDOCS_DIR/$folder" "$domain" "$PS_IMAGES_DOH" "$LOG_DIR" "$file" "$APP_NAME/$APP_VERSION" << 'EOF'
import os, shutil, signal, subprocess, sys, tempfile
root, domain, doh, logdir, listfile, agent = sys.argv[1:7]
rels = [l for l in open(listfile).read().split("\n") if l]
# (al cancelar la tarea se borra la carpeta temporal)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(130))
img = os.path.realpath(os.path.join(root, "img"))
got = gone = moved = blocked = 0
# El programa dice quien es (sin hacerse pasar por un navegador): si la web lo bloquea, se le da
# permiso en su servidor
agent = "%s (imagenes que faltan en una copia local)" % agent.replace(" ", "-")
with tempfile.TemporaryDirectory(dir=logdir, prefix="ps-imagenes-") as tmp:
    for start in range(0, len(rels), 300):
        batch = rels[start:start + 300]
        cfg = os.path.join(tmp, "curl.conf")
        with open(cfg, "w") as f:
            for n, rel in enumerate(batch):
                f.write('url = "https://%s/%s"\noutput = "%s/%d"\n' % (domain, rel, tmp, n))
        cmd = ["curl", "-s", "--parallel", "--parallel-max", "8", "-A", agent,
               "--proto", "=https", "--fail", "--max-redirs", "0", "--max-filesize", "30000000",
               "--connect-timeout", "15", "--max-time", "120", "-K", cfg,
               "-w", "%{exitcode} %{http_code} %{filename_effective}\n"]
        if doh:
            cmd[2:2] = ["--doh-url", doh]
        out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout
        for line in out.splitlines():
            code, http, name = (line.split(" ", 2) + ["", ""])[:3]
            n = os.path.basename(name)
            if not n.isdigit() or int(n) >= len(batch):
                continue
            src = os.path.join(tmp, n)
            dest = os.path.join(root, batch[int(n)])
            # (sin salir de img: una carpeta de la ruta podria ser un enlace a otro sitio. Se mira
            # antes de crear nada)
            real = os.path.realpath(os.path.dirname(dest))
            if code == "0" and http == "200" and os.path.isfile(src) and os.path.getsize(src) > 0 \
                    and real.startswith(img + os.sep) and not os.path.lexists(dest):
                os.makedirs(os.path.dirname(dest), mode=0o755, exist_ok=True)
                shutil.move(src, dest)
                got += 1
            elif http in ("301", "302", "307", "308"):
                moved += 1
            elif http in ("000", "401", "403", "429", "503"):
                blocked += 1
            else:
                gone += 1
            if os.path.lexists(src):
                os.remove(src)
        notes = [t % c for t, c in (("%d no estan en produccion", gone), ("%d bloqueadas por la web", blocked),
                                     ("%d con redireccion", moved)) if c]
        print("Descargadas %d de %d%s" % (got, len(rels), " (" + ", ".join(notes) + ")" if notes else ""), flush=True)
        # Lo primero, todo bloqueado: no se sigue llamando a la web
        if not got and blocked == len(batch):
            break
if blocked:
    print("La web de %s no deja descargar (cortafuegos o proteccion contra robots del servidor). Este" % domain)
    print("programa se presenta como «%s»: dale permiso en el servidor (Plesk: ModSecurity" % agent)
    print("o Imunify) o copia la carpeta img de produccion a mano")
if moved:
    print("Aviso: %d piden una redireccion (a www o a otro dominio): mira el dominio de la tienda" % moved)
print("Listo: %d imagenes nuevas en %s/img" % (got, root))
sys.exit(0 if got or not rels else 1)
EOF
    rc=$?
    rm -f "$file"
    return $rc
}

# Dominios .local apagados a mano en la pestaña Hosts: ya no se mantienen en /etc/hosts.
# local_off si|no <dominio...>: no = apagado (se recuerda), si = encendido (se olvida)
LOCAL_OFF_FILE="$HOME/.lvm-instalador/locales-apagados"
# (en simulacion no se guarda: los apagados van aqui, para que hosts_fake enseñe lo que haria)
LOCAL_OFF_DRY=""
function local_off() {
    local state=$1 d rest
    shift
    if [ "$DRY" -eq 1 ]; then
        [ "$state" == no ] && LOCAL_OFF_DRY+=" $*"
        echo "  [simulacion] $* $([ "$state" == no ] && echo "se recuerda apagado" || echo "se olvida como apagado") en $LOCAL_OFF_FILE"

        return 0
    fi
    mkdir -p -m 700 "$(dirname "$LOCAL_OFF_FILE")" || return 1
    rest=$(cat "$LOCAL_OFF_FILE" 2> /dev/null)
    for d in "$@"; do
        rest=$(grep -vxF -- "$d" <<< "$rest")
        [ "$state" == no ] && rest+=$'\n'"$d"
    done
    ( umask 077; sed '/^$/d' <<< "$rest" > "$LOCAL_OFF_FILE" )
}

# Para la pestaña Hosts: F|dominio|alias|carpeta|falseado (1/0)|https (1/0)|certificado (1/0)|PrestaShop (1/0)|personalizado (1/0)
function gui_hosts() {
    local info=$(vhosts_info) link=$(project_link)
    LVM_INFO=$info python3 -I - "$HOSTS_FILE" "$HTDOCS_DIR" "$PROJECT_VHOST $link" "$PORT_HTTPS" "$CUSTOM_DOMAINS_FILE" "$VHOSTS_FILE" <<'EOF'
import os, re, sys
hosts, htdocs, links, https_port, custom_file, vhosts = sys.argv[1:7]
# Dominio de produccion al que se piden las imagenes que faltan (media-produccion), por dominio
media, names = {}, []
try:
    for line in open(vhosts, errors="replace"):
        s = line.strip()
        if re.match(r"(?i)<VirtualHost\b", s):
            names = []
        w = s.split()
        if len(w) >= 2 and w[0].lower() in ("servername", "serveralias"):
            names += [n.lower().split(":")[0] for n in w[1:]]
        m = re.match(r"# nexum-media (\S+):", s)
        if m:
            for n in names:
                media[n] = m.group(1)
except OSError:
    pass
custom = set()
try:
    custom = {l.split("=", 1)[0] for l in open(custom_file) if "=" in l}
except OSError:
    pass
skip = set()
for l in links.split():
    skip |= {l, "www." + l}
active = set()
try:
    for line in open(hosts, errors="replace"):
        m = re.match(r"^\s*127\.0\.0\.1\s+(.*)", line)
        if m:
            active |= set(m.group(1).split("#")[0].lower().split())
except OSError:
    pass
rows = {}
for row in os.environ.get("LVM_INFO", "").splitlines():
    f = row.split("|")
    if len(f) < 6 or f[2] in skip:
        continue
    r = rows.setdefault(f[2], {"alias": "", "folder": "", "https": 0, "crt": 0})
    aliases = f[3].split()
    # El alias www.<dominio> si lo hay (algun vhost http tiene un alias copiado de otro)
    r["alias"] = ("www." + f[2]) if "www." + f[2] in aliases else (r["alias"] or (aliases or [""])[0])
    r["folder"] = r["folder"] or f[1]
    if f[0] == https_port:
        r["https"] = 1
        r["crt"] = int(bool(f[4]) and os.path.isfile(f[4]))
for name in sorted(rows):
    r = rows[name]
    ps = any(os.path.isfile(os.path.join(htdocs, r["folder"], p))
             for p in ("app/config/parameters.php", "config/settings.inc.php")) if r["folder"] else False
    print("F|%s|%s|%s|%d|%d|%d|%d|%d|%s" % (name, r["alias"], r["folder"], name in active,
                                            r["https"], r["crt"], ps, name in custom, media.get(name, "")))
# El vhost de los proyectos (web.local) tiene que llevar a 127.0.0.1, donde escucha Apache: si en
# hosts apunta a otra direccion (otra direccion de 127.x o de la red) o no esta, el
# navegador da ERR_CONNECTION_REFUSED. L|nombre|direccion a la que apunta ahora (vacio si no esta)
vhost_names = {row.split("|")[2].lower() for row in os.environ.get("LVM_INFO", "").splitlines()
               if len(row.split("|")) >= 3}
for name in dict.fromkeys(links.lower().split()):
    if not name or name not in vhost_names or name in active:
        continue
    now = ""
    try:
        for line in open(hosts, errors="replace"):
            w = line.split("#")[0].split()
            if len(w) >= 2 and name in [x.lower() for x in w[1:]]:
                now = w[0]
                break
    except OSError:
        pass
    print("L|%s|%s" % (name, re.sub(r"[^0-9A-Fa-f.:]", "", now)))
EOF
}

# Ficheros y carpetas de htdocs que puede cambiar cualquier usuario del Mac (plugins y caches que
# los dejan en 777 o 666): otro usuario podria dejar un PHP y ejecutarlo con el tuyo pidiendolo a
# localhost. Se les quita la escritura para los demas (Apache, que corre con tu usuario, sigue
# pudiendo escribir). Solo lo tuyo y con tu usuario (sin sudo: root no cambia permisos dentro de
# htdocs, que es tuyo); de lo de otros solo se avisa. htdocs_close_world <carpeta>
function htdocs_close_world() {
    local dir=$1 me n others
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 0
    me=$(id -un)
    # Una sola pasada (al cargar un proyecto con vendor o node_modules, cuenta): lo tuyo se cambia
    # y se cuenta a la vez. Lo de otros usuarios solo se mira con --otros (Protegerlas)
    if [ "$DRY" -eq 1 ]; then
        n=$(find "$dir" -xdev \( -type f -o -type d \) -perm -0002 -user "$me" -print 2> /dev/null | wc -l | tr -d ' ')
        [ "$n" -gt 0 ] && echo "  [simulacion] $n ficheros y carpetas de $dir dejarian de poder cambiarlos los demas usuarios"
    elif [ "$2" == "--otros" ]; then
        # Una sola pasada tambien aqui: lo tuyo se cambia y se cuenta, y lo de otros solo se cuenta
        local list
        list=$(find "$dir" -xdev \( -type f -o -type d \) -perm -0002 \
            \( -user "$me" -exec chmod o-w {} + -exec echo m \; -o -exec echo o \; \) 2> /dev/null)
        n=$(grep -c '^m$' <<< "$list") others=$(grep -c '^o$' <<< "$list")
        [ "$n" -gt 0 ] && echo "$n ficheros y carpetas de $dir ya no los puede cambiar cualquier usuario"
        [ "$others" -gt 0 ] && echo "Aviso: $others de $dir son de otro usuario y los puede cambiar cualquiera: revisalos (sudo chmod o-w)"
        return 0
    else
        n=$(find "$dir" -xdev \( -type f -o -type d \) -perm -0002 -user "$me" -exec chmod o-w {} + -print 2> /dev/null | wc -l | tr -d ' ')
        [ "$n" -gt 0 ] && echo "$n ficheros y carpetas de $dir ya no los puede cambiar cualquier usuario del Mac"
    fi
    return 0
}

# Tu usuario (el de SUDO_USER si esto corre con sudo), para Apache, PHP-FPM y los permisos: solo un
# nombre valido de un usuario que existe (va a la configuracion que lee root). Si no, el que corre
function web_user_name() {
    local u=${SUDO_USER:-$USER}
    if [[ "$u" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,31}$ ]] && id "$u" > /dev/null 2>&1; then
        echo "$u"
    else
        id -un
    fi
}

# Proyectos nuevos con dominio falseado (pestaña Hosts): dominio=carpeta, uno por linea
CUSTOM_DOMAINS_FILE="$HOME/.lvm-instalador/dominios"

# Dominio personalizado de una carpeta (vacio si no tiene)
function custom_domain() {
    local d
    [ -f "$CUSTOM_DOMAINS_FILE" ] || return 0
    d=$(awk -F= -v f="$1" '$2 == f { d = $1 } END { if (d != "") print d }' "$CUSTOM_DOMAINS_FILE")
    # El fichero es tuyo: solo un dominio valido (sin /, .., espacios ni saltos de linea)
    [ -n "$d" ] && valid_domain "$d" && echo "$d"
    return 0
}

# nuevo-dominio <dominio> <carpeta> [base]: proyecto nuevo con el dominio de produccion falseado.
# Crea la carpeta en htdocs, su vhost http y https con certificado (lo mismo que una tienda
# PrestaShop), la base vacia con el nombre de produccion en la version activa (si se indica y no
# existe) y falsea el dominio (los demas dejan de estarlo, como al cargar un proyecto). El dominio
# queda asociado a la carpeta: Cargar proyecto lo vuelve a falsear.
function new_custom_domain() {
    local domain=$(tr 'A-Z' 'a-z' <<< "$1") folder=${2%/} db=$3 link owner s=""

    if ! valid_domain "$domain"; then
        echo "Dominio no valido: $1 (por ejemplo: mitienda.com)"

        return 1
    fi
    for link in localhost "$PROJECT_VHOST" $(project_link); do
        if [ "$domain" == "$link" ] || [ "$domain" == "www.$link" ] || [ "$folder" == "$link" ]; then
            echo "$link es el de los proyectos o el del equipo: elige otro dominio y otra carpeta"

            return 1
        fi
    done
    if ! [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
        echo "Carpeta no valida: $folder (solo letras sin acentos, numeros, punto, _ y -)"

        return 1
    fi
    if [ -L "$HTDOCS_DIR/$folder" ]; then
        echo "$HTDOCS_DIR/$folder es un enlace, no una carpeta de proyecto"

        return 1
    fi
    owner=$(vhosts_info | awk -F'|' -v d="$domain" '$3 == d || index(" " $4 " ", " " d " ") { print $2; exit }')
    if [ -n "$owner" ]; then
        echo "Ya hay un vhost para $domain (carpeta ${owner:-desconocida}). Para falsearlo usa su"
        echo "interruptor en Dominios y hosts (o: lvm-instalador hosts-falsear $domain si)."

        return 1
    fi
    if [ -n "$db" ]; then
        db_valid_name "$db" || return 1
    fi

    if [ -d "$HTDOCS_DIR/$folder" ]; then
        echo "Se usa la carpeta que ya existe: $HTDOCS_DIR/$folder"
    else
        echo "Creando la carpeta $HTDOCS_DIR/$folder..."
        [ -w "$HTDOCS_DIR" ] || s=$SUDO
        run $s mkdir -p "$HTDOCS_DIR/$folder" || return 1
        [ -n "$s" ] && run $SUDO chown "${SUDO_USER:-$USER}:$(id -gn "${SUDO_USER:-$USER}")" "$HTDOCS_DIR/$folder"
    fi

    PS_RELOAD=0
    ps_vhost "$folder" "$domain" || return 1

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $domain=$folder en $CUSTOM_DOMAINS_FILE"
    else
        mkdir -p "$(dirname "$CUSTOM_DOMAINS_FILE")"
        { [ -f "$CUSTOM_DOMAINS_FILE" ] && grep -v "^$domain=" "$CUSTOM_DOMAINS_FILE"; echo "$domain=$folder"; } > "$CUSTOM_DOMAINS_FILE.nuevo"
        mv "$CUSTOM_DOMAINS_FILE.nuevo" "$CUSTOM_DOMAINS_FILE"
    fi

    if [ -n "$db" ]; then
        if db_connect > /dev/null 2>&1 && db_exists "$db"; then
            echo "La base de datos $db ya existe en XAMPP-$DB_FOLDER: se deja como esta"
        else
            create_database "$db" || echo "Aviso: no se ha creado la base $db. Creala despues en la pestaña Bases de datos."
        fi
        # Cargar proyecto desde el buscador de bases encuentra la carpeta aunque aun no haya configuracion
        if [ "$DRY" -eq 0 ]; then
            remember_project "$db" "$folder"
        fi
    fi

    hosts_fake cargar "$domain" || return 1
    if [ "$PS_RELOAD" -eq 1 ] && [ -f "$LINK/xamppfiles/logs/httpd.pid" ]; then
        echo "Recargando Apache para aplicar el vhost y el certificado..."
        run xampp_ctl reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi
    echo "Proyecto nuevo listo: https://$domain -> $HTDOCS_DIR/$folder$([ -n "$db" ] && echo " (base $db)")"
}

