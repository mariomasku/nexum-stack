# El usuario, la contraseña y la base del proyecto en LAMPP (los de su wp-config.php o, en una tienda, los
# de su app/config/parameters.php o config/settings.inc.php): usuario|base y la contraseña en la segunda linea
function lampp_bd_creds() {
    python3 -I - "$HTDOCS_DIR/$1" << 'EOF'
import os, re, sys
root = sys.argv[1]
def read(rel):
    p = os.path.join(root, rel)
    if not os.path.isfile(p) or os.path.islink(p):
        return None
    try:
        return open(p, encoding="utf-8", errors="replace").read(2000000)
    except OSError:
        return None
def unq(m):
    return re.sub(r"\\(.)", r"\1", m.group(1) if m.group(1) is not None else m.group(2))
def define(text, name):
    m = re.search(r"""(?m)^(?:(?!//|#)[^\n])*?\bdefine\(\s*['"]%s['"]\s*,\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""" % name, text)
    return None if not m else unq(m)
def param(text, key):
    m = re.search(r"""['"]%s['"]\s*=>\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""" % key, text)
    return None if not m else unq(m)
text = read("wp-config.php")
if text is not None:
    user, db, pw = define(text, "DB_USER"), define(text, "DB_NAME"), define(text, "DB_PASSWORD")
else:
    text = read("app/config/parameters.php")
    if text is not None:
        user, db, pw = param(text, "database_user"), param(text, "database_name"), param(text, "database_password")
    else:
        text = read("config/settings.inc.php") or ""
        user, db, pw = define(text, "_DB_USER_"), define(text, "_DB_NAME_"), define(text, "_DB_PASSWD_")
if not user or not db or pw is None or "\n" in pw or "|" in user + db:
    sys.exit(1)
print(user + "|" + db)
print(pw)
EOF
}

# El dominio de una tienda en vivo (el de su shop_url principal, tal cual: con su www si lo lleva), leido por
# el puente hasta la MariaDB de esa version con el usuario del proyecto. Vacio si no se encuentra
# lampp_bd_shop_domain <version duena> <base> <usuario> <contraseña>
function lampp_bd_shop_domain() {
    local f=$1 db=$2 user=$3 pass=$4 prefix dom
    local sql=(dk run --rm -i --network nexum -e MYSQL_PWD "$LAMPP_BD_BRIDGE_IMAGE" mariadb -h "$(lampp_bd_bridge "$f")" -u "$user" -N "$db")
    prefix=$(MYSQL_PWD=$pass "${sql[@]}" <<< "SELECT LEFT(table_name, LENGTH(table_name) - 8) FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name LIKE '%shop\\_url' AND table_type = 'BASE TABLE' LIMIT 1;" 2> /dev/null | tr -d '\r')
    [[ "$prefix" =~ ^[A-Za-z0-9_]+$ ]] || return 0
    dom=$(MYSQL_PWD=$pass "${sql[@]}" <<< "SELECT IF(domain_ssl <> '', domain_ssl, domain) FROM \`${prefix}shop_url\`
        ORDER BY main DESC, active DESC, id_shop_url LIMIT 1;" 2> /dev/null | tr -d '\r' | tr 'A-Z' 'a-z')
    dom=${dom%%:*}
    valid_domain "$dom" && echo "$dom"
    return 0
}

# Tienda que pasa a su BBDD en vivo (con el puente ya en marcha): su dominio de verdad a proyecto.conf
# (DOMINIO_TIENDA, y PRODUCCION para traer de alli sus imagenes) y su compose.yaml al dia (en el Mac, la web
# del contenedor espera ese dominio). Sin dominio en su BBDD, no se puede servir: error
function lampp_bd_shop_live() {
    local slug=$1 dir=$DOCKER_DIR/$1 dom
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] dominio de la tienda, de su shop_url"; return 0; }
    dom=$(lampp_bd_shop_domain "$(docker_conf "$slug" LAMPP_BD)" "$(docker_conf "$slug" BBDD)" "$(docker_conf "$slug" USUARIO)" \
        "$(sed -n 's/^DB_PASS=//p' "$dir/.env")")
    if [ -z "$dom" ]; then
        echo "No se ha podido leer el dominio de la tienda en su BBDD ($(docker_conf "$slug" BBDD), tabla shop_url): mira su usuario y su contraseña"
        return 1
    fi
    echo "Tienda en vivo: sigue en $dom en su BBDD (no se toca); el Apache de Docker la enseña en $(docker_web_url "$(docker_conf "$slug" DOMINIO)")"
    docker_conf_set "$slug" DOMINIO_TIENDA "$dom" || return 1
    [[ "$dom" != *.local && "$dom" != *.docker.test && "$dom" != *.docker.local ]] && docker_conf_set "$slug" PRODUCCION "${dom#www.}"
    docker_web_compose "$slug"
}
