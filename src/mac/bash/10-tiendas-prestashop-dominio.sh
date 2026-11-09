# ===========================================================================
# Tiendas PrestaShop: dominio propio, certificado y /etc/hosts falseado
# ===========================================================================
# PrestaShop redirige siempre al dominio guardado en su base (tabla shop_url), asi que no se puede
# ver por web.local. Se monta como en el manual de XAMPP del equipo: un vhost por dominio (http y
# https) con DocumentRoot en la carpeta del proyecto, un certificado autofirmado (en el Mac, en
# XAMPP-compartido/ssl, junto al de web.local) y el dominio falseado en /etc/hosts (127.0.0.1 y ::1).
# Al cargar otro proyecto, el dominio deja de estar falseado y vuelve a llevar a la web real.
# (LVM_SSL_CERTS/LVM_SSL_KEYS solo para pruebas)
SSL_CERTS_DIR=${LVM_SSL_CERTS:-$COMMON/ssl}
SSL_KEYS_DIR=${LVM_SSL_KEYS:-$COMMON/ssl}
OWN_SSL_DIR=$COMMON/ssl

# Base de datos y prefijo de tablas de una tienda PrestaShop: base|prefijo. Nada si no lo es.
function ps_config() {
    python3 -I - "$HTDOCS_DIR/$1" <<'EOF'
import os, re, sys
root = sys.argv[1]
rules = [
    ("app/config/parameters.php",
     r"""['"]database_name['"]\s*=>\s*['"]([^'"]+)""", r"""['"]database_prefix['"]\s*=>\s*['"]([^'"]*)"""),
    ("config/settings.inc.php",
     r"""define\(\s*['"]_DB_NAME_['"]\s*,\s*['"]([^'"]+)""", r"""define\(\s*['"]_DB_PREFIX_['"]\s*,\s*['"]([^'"]*)"""),
]
for rel, rx_db, rx_prefix in rules:
    try:
        if not os.path.isfile(os.path.join(root, rel)) or os.path.getsize(os.path.join(root, rel)) > 2000000:
            raise OSError("no es un fichero normal")
        with open(os.path.join(root, rel), errors="replace") as f:
            text = f.read()
    except OSError:
        continue
    db, prefix = re.search(rx_db, text), re.search(rx_prefix, text)
    if db:
        print("%s|%s" % (db.group(1), prefix.group(1) if prefix else "ps_"))
        break
EOF
}

# Virtual hosts sin comentar de VHOSTS_FILE: puerto|carpeta de htdocs|ServerName|alias|certificado|clave
function vhosts_info() {
    [ -f "$VHOSTS_FILE" ] || return 0
    python3 -I - "$VHOSTS_FILE" <<'EOF'
import re, sys
block = None
for raw in open(sys.argv[1], errors="replace"):
    line = raw.split("#", 1)[0].strip() if raw.lstrip().startswith("#") else raw.strip()
    if not line:
        continue
    m = re.match(r"<VirtualHost\s+[^>]*:(\d+)\s*>", line, re.I)
    if m:
        block = {"port": m.group(1), "folder": "", "name": "", "alias": [], "crt": "", "key": ""}
        continue
    if block is None:
        continue
    if re.match(r"</VirtualHost>", line, re.I):
        if block["name"]:
            print("|".join([block["port"], block["folder"], block["name"].lower(),
                            " ".join(a.lower() for a in block["alias"]), block["crt"], block["key"]]))
        block = None
        continue
    key, value = (re.split(r"\s+", line, maxsplit=1) + [""])[:2]
    value = value.strip().strip('"')
    key = key.lower()
    if key == "documentroot":
        m = re.search(r"/htdocs/([^/\s]+)", value)
        block["folder"] = m.group(1) if m else ""
    elif key == "servername":
        block["name"] = value.split(":")[0]
    elif key == "serveralias":
        block["alias"] += value.split()
    elif key == "sslcertificatefile":
        block["crt"] = value
    elif key == "sslcertificatekeyfile":
        block["key"] = value
EOF
}

function valid_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]
}

# Certificado autofirmado (no de CA) de <dominio> y <alias> en <crt> y su clave en <key>:
# make_selfsigned <dominio> <alias> <crt> <key>. openssl corre con tu usuario en una carpeta temporal
# tuya y lo hecho se instala (con sudo si la carpeta es de root) solo si <crt> y <key> estan en las
# carpetas de certificados del gestor: las rutas de un vhost las puede haber escrito cualquier programa
# tuyo (la copia de los vhosts es tuya) y root no debe crear ni machacar ficheros donde digan.
function make_selfsigned() {
    local cn=$1 alt=$2 crt=$3 key=$4 tmp s="" d ok_crt=0 ok_key=0 openssl=/usr/bin/openssl
    # El de Homebrew (si esta) corre con tu usuario: es tuyo, pero ya no como root
    command -v brew > /dev/null && [ -x "$(brew --prefix openssl@3 2> /dev/null)/bin/openssl" ] \
        && openssl="$(brew --prefix openssl@3)/bin/openssl"
    for d in "$SSL_CERTS_DIR" "$OWN_SSL_DIR"; do [ "$(dirname "$crt")" == "$d" ] && ok_crt=1; done
    for d in "$SSL_KEYS_DIR" "$OWN_SSL_DIR"; do [ "$(dirname "$key")" == "$d" ] && ok_key=1; done
    if [ $ok_crt -eq 0 ] || [ $ok_key -eq 0 ] || ! [[ "$(basename "$crt")" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(crt|pem)$ ]] \
            || ! [[ "$(basename "$key")" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(key|pem)$ ]] || ! valid_domain "$cn"; then
        echo "El certificado de $cn ($crt) no esta en la carpeta de certificados del gestor ($OWN_SSL_DIR): no se crea."
        echo "Pulsa Arreglarlos en el aviso de certificados (Versiones) o: lvm-instalador arreglar-certificados"
        return 1
    fi
    { [ -d "$(dirname "$crt")" ] && [ -w "$(dirname "$crt")" ] && [ -w "$(dirname "$key")" ]; } || s=$SUDO
    [ -d "$(dirname "$crt")" ] && [ -d "$(dirname "$key")" ] || run $s mkdir -p "$(dirname "$crt")" "$(dirname "$key")" || return 1
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] certificado autofirmado de $cn en $crt (clave en $key)"
        return 0
    fi
    # Como root, solo en carpetas de root sin enlaces (la carpeta ssl y XAMPP-compartido) y sin un
    # enlace en el destino: si no, root escribiria a traves de el en otro fichero del Mac
    if [ -n "$s" ]; then
        for d in "$(dirname "$crt")" "$(dirname "$key")" "$COMMON"; do
            if [ -L "$d" ] || [ "$(stat -f %u "$d" 2> /dev/null)" != 0 ]; then
                echo "No se crea el certificado de $cn: $d no es una carpeta del administrador (vuelve a protegerla)"
                return 1
            fi
        done
        if [ -L "$crt" ] || [ -L "$key" ]; then
            echo "No se crea el certificado de $cn: $crt o $key es un enlace"
            return 1
        fi
    fi
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-cert.XXXXXX") || return 1
    # Las extensiones van en un fichero de configuracion (la LibreSSL de macOS 12 no tiene -addext)
    printf '[req]\ndistinguished_name = dn\nx509_extensions = ext\nprompt = no\n[dn]\nCN = %s\n[ext]\nbasicConstraints = critical,CA:FALSE\nsubjectAltName = DNS:%s\n' \
        "$cn" "$cn${alt:+,DNS:$alt}" > "$tmp/cnf"
    if ! (umask 077; "$openssl" req -x509 -nodes -newkey rsa:2048 -days 3650 -config "$tmp/cnf" \
            -keyout "$tmp/key" -out "$tmp/crt") > /dev/null 2>&1; then
        rm -rf "$tmp"
        echo "No se ha podido crear el certificado de $cn"
        return 1
    fi
    if [ -n "$s" ]; then
        # Los abre tu usuario (redireccion) y root solo escribe: si mientras tanto cambiaran el
        # temporal por un enlace a un fichero de root, root no lo copiaria
        $s sh -c 'umask 022; cat > "$1"' sh "$crt" < "$tmp/crt" && $s chown root:wheel "$crt" && $s chmod 644 "$crt" \
            && $s sh -c 'umask 077; cat > "$1"' sh "$key" < "$tmp/key" && $s chown root:wheel "$key" && $s chmod 600 "$key"
    else
        install -m 644 "$tmp/crt" "$crt" && install -m 600 "$tmp/key" "$key"
    fi || { rm -rf "$tmp"; echo "No se ha podido guardar el certificado de $cn"; return 1; }
    rm -rf "$tmp"
    return 0
}

