# El usuario, la contraseña y la base del proyecto en LAMPP (los de su wp-config.php): usuario|base y la
# contraseña en la segunda linea
function lampp_bd_creds() {
    python3 -I - "$HTDOCS_DIR/$1/wp-config.php" << 'EOF'
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read(2000000)
except OSError:
    sys.exit(1)
def get(name):
    m = re.search(r"""(?m)^(?:(?!//|#)[^\n])*?\bdefine\(\s*['"]%s['"]\s*,\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""" % name, text)
    return None if not m else re.sub(r"\\(.)", r"\1", m.group(1) if m.group(1) is not None else m.group(2))
user, db, pw = get("DB_USER"), get("DB_NAME"), get("DB_PASSWORD")
if not user or not db or pw is None or "\n" in pw or "|" in user + db:
    sys.exit(1)
print(user + "|" + db)
print(pw)
EOF
}

