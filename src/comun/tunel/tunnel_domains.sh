# Los dominios que el tunel cambia por el suyo (en las paginas, las cabeceras y las redirecciones), uno
# por linea: tunnel_domains <dominio compartido> [carpeta real del proyecto]. El compartido y, de su
# proyecto, los que estan falseados en este equipo (llevan a 127.x): el de su base (WordPress: home o
# siteurl; PrestaShop: shop_url), los ServerName y ServerAlias de sus vhosts y, si es el cargado, los
# de web.local. Asi quien lo recibe ve lo mismo que tu, con el dominio real falseado incluido. Uno que
# no este falseado no se cambia: el tunel nunca lleva a una web de fuera
function tunnel_domains() {
    local host=$1 dir=$2 folder link names=()
    if [ -n "$dir" ]; then
        folder=$(basename "$dir")
        if is_prestashop "$folder" 2> /dev/null; then
            names+=("$(ps_domain "$folder" 2> /dev/null)")
        elif [ -f "$dir/wp-config.php" ]; then
            names+=("$(gui_wp_prod "$folder" 2> /dev/null | sed -n 's/^D|//p' | head -1)")
        fi
        link=$(project_link 2> /dev/null)
        [ -n "$link" ] && [ "$(readlink "$HTDOCS_DIR/$link" 2> /dev/null | sed 's:/*$::')" == "$folder" ] || link=""
        names+=($(vhosts_info 2> /dev/null | awk -F'|' -v f="$folder" -v l="$link" '$2 == f || (l != "" && $2 == l) { print $3 " " $4 }'))
    fi
    printf '%s\n' "${names[@]}" | tr 'A-Z' 'a-z' | while read -r n; do
        valid_domain "$n" 2> /dev/null && echo "$n"
    done | python3 -I -c '
import socket, sys
host, seen = sys.argv[1], set()
print(host)
seen.add(host)
for n in sys.stdin.read().split():
    if n in seen:
        continue
    seen.add(n)
    try:
        ips = {a[4][0] for a in socket.getaddrinfo(n, None, socket.AF_INET)}
    except OSError:
        continue
    if ips and all(ip.startswith("127.") for ip in ips):
        print(n)
' "$host"
}
