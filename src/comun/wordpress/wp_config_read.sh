# Datos de un wp-config.php, uno por linea: base, usuario, servidor, prefijo y contraseña
function wp_config_read() {
    python3 -I - "$1" <<'EOF'
import os, re, sys
try:
    if not os.path.isfile(sys.argv[1]) or os.path.getsize(sys.argv[1]) > 2000000:
        raise OSError("no es un fichero normal")
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        text = f.read()
except OSError:
    sys.exit(1)
def const(name):
    # Solo las que no estan comentadas (// define( 'DB_USER', 'development' );)
    m = re.search(r"""(?m)^[ \t]*define\(\s*['"]%s['"]\s*,\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""" % name, text)
    if not m:
        return ""
    return re.sub(r"\\(.)", r"\1", m.group(1) if m.group(1) is not None else m.group(2))
m = re.search(r"""(?m)^[ \t]*\$table_prefix\s*=\s*['"]([^'"]*)['"]""", text)
# Sin caracteres de control (salen en la terminal: un ESC cambiaria lo que se ve), salvo en la
# contraseña, que no se muestra
for i, v in enumerate((const("DB_NAME"), const("DB_USER"), const("DB_HOST"), m.group(1) if m else "", const("DB_PASSWORD"))):
    print(v.replace("\n", " ") if i == 4 else re.sub(r"[\x00-\x1f\x7f-\x9f]", "?", v))
EOF
}

