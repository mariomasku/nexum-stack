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

