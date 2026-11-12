# ===========================================================================
# Proyectos de htdocs
# ===========================================================================

# Enlace de htdocs al que apunta el DocumentRoot de un vhost (por ejemplo web.local). Vacio si no hay.
# (python: el grep de macOS no tiene -P)
function project_link() {
    [ -f "$VHOSTS_FILE" ] || return 1
    python3 -I - "$VHOSTS_FILE" "$HTDOCS_DIR" <<'EOF'
import os, re, sys
seen = []
with open(sys.argv[1], errors="replace") as f:
    for line in f:
        if line.lstrip().startswith("#"):
            continue
        m = re.search(r"""DocumentRoot\s+"?[^"\s]*/htdocs/([^/"\s]+)""", line)
        if m and m.group(1) not in seen:
            seen.append(m.group(1))
for name in seen:
    if os.path.islink(os.path.join(sys.argv[2], name)):
        print(name)
        sys.exit(0)
sys.exit(1)
EOF
}

# Para la ventana: E|enlace|carpeta a la que apunta, P|carpeta|base de datos|.php-version|tipo por
# cada proyecto (base leida de wp-config.php, PrestaShop o .env; tipo ps o wp) y R|base|carpeta
# recordadas
function gui_projects() {
    local link=$(project_link)

    # Sin vhost: se creara web.local al cargar el primer proyecto (cuarto campo N)
    if [ -z "$link" ]; then
        echo "E|$PROJECT_VHOST||N"
    else
        # (sin proyecto cargado, el enlace apunta a la pagina vacia: carpeta vacia para la ventana)
        echo "E|$link|$(readlink "$HTDOCS_DIR/$link" | sed 's:/*$::' | grep -vxF "$EMPTY_PROJECT")"
    fi
    [ -d "$HTDOCS_DIR" ] || return 1
    python3 -I - "$HTDOCS_DIR" <<'EOF'
import os, re, sys
root = sys.argv[1]
rules = [
    ("wp-config.php", r"""^[ \t]*define\(\s*['"]DB_NAME['"]\s*,\s*['"]([^'"]+)"""),
    ("app/config/parameters.php", r"""['"]database_name['"]\s*=>\s*['"]([^'"]+)"""),
    ("config/settings.inc.php", r"""define\(\s*['"]_DB_NAME_['"]\s*,\s*['"]([^'"]+)"""),
    (".env", r"""^\s*DB_DATABASE\s*=\s*["']?([^"'\s#]+)"""),
]
for name in sorted(os.listdir(root), key=str.lower):
    path = os.path.join(root, name)
    # Un nombre con | o saltos de linea romperia las lineas que lee la ventana
    if name.startswith(".") or re.search(r"[|\x00-\x1f]", name) or os.path.islink(path) \
            or not os.path.isdir(path):
        continue
    db = ""
    for rel, rx in rules:
        try:
            if not os.path.isfile(os.path.join(path, rel)) or os.path.getsize(os.path.join(path, rel)) > 2000000:
                raise OSError("no es un fichero normal")
            with open(os.path.join(path, rel), errors="replace") as f:
                m = re.search(rx, f.read(), re.M)
        except OSError:
            continue
        if m:
            db = m.group(1)
            break
    # Solo nombres de base validos (la configuracion la trae el proyecto)
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", db):
        db = ""
    ver = ""
    try:
        if not os.path.isfile(os.path.join(path, ".php-version")) or os.path.getsize(os.path.join(path, ".php-version")) > 2000000:
            raise OSError("no es un fichero normal")
        with open(os.path.join(path, ".php-version")) as f:
            ver = re.sub(r"[^0-9.]", "", f.read().strip())[:16]
    except OSError:
        pass
    # Tipo: ps (tienda PrestaShop, como is_prestashop) o wp (WordPress)
    kind = ""
    if "prestashop" in name.lower() or os.path.isdir(os.path.join(path, "src/PrestaShopBundle")) \
            or os.path.isfile(os.path.join(path, "classes/PrestaShopAutoload.php")):
        kind = "ps"
    elif os.path.isfile(os.path.join(path, "wp-config.php")) or \
            os.path.isdir(os.path.join(path, "wp-includes")):
        kind = "wp"
    print("P|%s|%s|%s|%s" % (name, db, ver, kind))
EOF
    [ -f "$PROJECTS_FILE" ] && grep -E '^[A-Za-z0-9_][A-Za-z0-9_-]*=[^|]+$' "$PROJECTS_FILE" | sed 's/^\([^=]*\)=/R|\1|/'
    # V|base|version|carpeta: los vinculos de una version (sin carpeta: desvinculada en esa version)
    [ -f "$PROJECTS_FILE" ] && grep -E '^[A-Za-z0-9_][A-Za-z0-9_-]*@[A-Za-z0-9._-]+=[^|]*$' "$PROJECTS_FILE" \
        | sed 's/^\([^@]*\)@\([^=]*\)=/V|\1|\2|/'
    return 0
}

# Crea el vhost web.local (http y https, sin cache en el navegador) con DocumentRoot en el enlace
# htdocs/web.local, su certificado autofirmado y su linea en /etc/hosts. Lo usa load_project cuando
# ningun vhost apunta a un enlace de htdocs (la primera vez en un Mac: httpd-vhosts.conf esta vacio).
function create_project_vhost() {
    local name=$PROJECT_VHOST s="" ssl=$COMMON/ssl openssl=/usr/bin/openssl

    if [ -e "$HTDOCS_DIR/$name" ] && [ ! -L "$HTDOCS_DIR/$name" ]; then
        echo "$HTDOCS_DIR/$name ya existe y no es un enlace. Cambiale el nombre para poder crear el vhost $name."

        return 1
    fi
    if [ -f "$VHOSTS_FILE" ] && grep -v '^[[:space:]]*#' "$VHOSTS_FILE" \
        | grep -qiE "^[[:space:]]*ServerName[[:space:]]+${name//./\\.}(:[0-9]+)?[[:space:]]*$"; then
        echo "Ya hay un vhost $name en $VHOSTS_FILE, pero su DocumentRoot no es el enlace $HTDOCS_DIR/$name."
        echo "Cambia su DocumentRoot a \"$LINK/xamppfiles/htdocs/$name\" y vuelve a cargar el proyecto."

        return 1
    fi

    echo "Creando el vhost $name (http y https) en $VHOSTS_FILE..."
    [ -w "$(dirname "$VHOSTS_FILE")" ] || s=$SUDO
    make_selfsigned "$name" "www.$name" "$ssl/$name.crt" "$ssl/$name.key" || return 1

    local admin=$(server_admin)
    local block="
# $name: apunta al proyecto cargado (enlace $HTDOCS_DIR/$name), creado por nexum
<VirtualHost *:$PORT_HTTP>
    ServerAdmin $admin
    DocumentRoot \"$LINK/xamppfiles/htdocs/$name\"
    ServerName $name
    ServerAlias www.$name
    # Sin cache en el navegador: al cambiar de proyecto no sale el anterior
    <IfModule headers_module>
        Header always set Cache-Control \"no-store\"
    </IfModule>
</VirtualHost>

<VirtualHost *:$PORT_HTTPS>
    ServerAdmin $admin
    DocumentRoot \"$LINK/xamppfiles/htdocs/$name\"
    ServerName $name
    ServerAlias www.$name
    SSLEngine on
    SSLCertificateFile \"$ssl/$name.crt\"
    SSLCertificateKeyFile \"$ssl/$name.key\"
    <IfModule headers_module>
        Header always set Cache-Control \"no-store\"
    </IfModule>
</VirtualHost>"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] añadir a $VHOSTS_FILE:$block"
    else
        # (como root, solo en el fichero de XAMPP-compartido y sin enlaces: ver vhosts_path_ok)
        if [ -n "$s" ] && ! vhosts_path_ok; then
            echo "No se añade el vhost: $VHOSTS_FILE tiene que ser un fichero normal de $COMMON (sin enlaces)."
            return 1
        fi
        printf '%s\n' "$block" | $s tee -a "$VHOSTS_FILE" > /dev/null || return 1
    fi

    # .local: sin la linea en /etc/hosts, macOS lo busca por Bonjour y tarda segundos (tambien en IPv6)
    if ! grep -qE "^[^#]*[[:space:]]${name//./\\.}([[:space:]]|$)" "$HOSTS_FILE" 2> /dev/null; then
        echo "Añadiendo $name a $HOSTS_FILE..."
        [ -w "$HOSTS_FILE" ] && s="" || s=sudo
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] 127.0.0.1 y ::1 $name www.$name en $HOSTS_FILE"
        else
            printf '127.0.0.1 %s www.%s\n::1 %s www.%s\n' "$name" "$name" "$name" "$name" | $s tee -a "$HOSTS_FILE" > /dev/null || return 1
            [ "$HOSTS_FILE" == /etc/hosts ] && { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; } 2> /dev/null
        fi
    fi

    return 0
}

#@incluir comun/proyectos-opt-htdocs/valid_project.sh
#@incluir comun/proyectos-opt-htdocs/vhosts_orphans.sh
# exportar-proyecto: la carpeta de descargas (~/Downloads) y el nombre de una version (XAMPP-8.4.27)
function export_downloads() { echo "$HOME/Downloads"; }
function export_version_label() { echo "XAMPP-$1"; }
#@incluir comun/proyectos-opt-htdocs/project_export.sh
# ¿Se puede escribir este fichero sin salirse de la carpeta del proyecto? Ni el fichero ni las
# carpetas de su ruta pueden ser enlaces que lleven fuera: un repositorio podria traer wp-config.php
# como enlace a un fichero del sistema, y con sudo se escribiria encima.
function project_path_ok() {
    local root=$1 path=$2 real_root real_dir
    [ -L "$path" ] && return 1
    real_root=$(realpath_f "$root") real_dir=$(realpath_f "$(dirname "$path")")
    [ -n "$real_root" ] && [[ "$real_dir" == "$real_root" || "$real_dir" == "$real_root"/* ]]
}

# Escribe un fichero de un proyecto, con sudo si es de otro usuario. Con sudo se borra antes y se
# crea de nuevo, tuyo: si entre medias lo cambiaran por un enlace, se borraria el enlace y no el
# fichero al que apunta.
# Con sudo, root recorre la ruta carpeta a carpeta sin seguir enlaces (si entre medias cambiaran una
# carpeta por un enlace, falla en lugar de escribir en otro sitio), borra el fichero y lo crea de
# nuevo, tuyo. El contenido lo lee tu usuario (root no abre el fichero de origen).
PROJECT_WRITE_PY='
import os, sys
dest, uid, gid, top = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
data = sys.stdin.buffer.read()
# La carpeta se resuelve aqui (como root, no antes con tu usuario) y tiene que quedar dentro de
# htdocs: si un proyecto se cambia por un enlace a otra carpeta del sistema, no se escribe alli
top = os.path.realpath(top)
real = os.path.join(os.path.realpath(os.path.dirname(dest)), os.path.basename(dest))
if not (real.startswith(top + "/") and os.path.basename(dest) not in ("", ".", "..")):
    sys.exit("%s no esta dentro de %s: no se escribe" % (dest, top))
parts = [p for p in real.split("/") if p]
fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
for p in parts[:-1]:
    nfd = os.open(p, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
    os.close(fd)
    fd = nfd
name = parts[-1]
try:
    os.unlink(name, dir_fd=fd)
except FileNotFoundError:
    pass
out = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=fd)
os.write(out, data)
os.fchown(out, uid, gid)
os.close(out)
'
function project_write() {
    local src=$1 dest=$2
    if [ -w "$dest" ] || { [ ! -e "$dest" ] && [ -w "$(dirname "$dest")" ]; }; then
        run cp "$src" "$dest"
    else
        [ -d "$(dirname "$dest")" ] || return 1
        if [ "$DRY" -eq 1 ] || [ -z "$SUDO" ]; then
            run cp "$src" "$dest"
            return
        fi
        $SUDO python3 -I -c "$PROJECT_WRITE_PY" "$dest" "$(id -u)" "$(id -g)" "$HTDOCS_DIR" < "$src"
    fi
}

# Carpeta oculta de htdocs a la que apunta el enlace del vhost de los proyectos (web.local) cuando no
# hay ninguno cargado: una pagina que lo dice (no sale en la lista de proyectos)
EMPTY_PROJECT=.lvm-sin-proyecto

# empty_page <carpeta>: su index.html, con el logotipo y el nombre de Nexum Dev Stack (en Goldman, que
# va dentro de la pagina con el logotipo: sin nada que pedir a otro sitio). Solo se escribe si ha
# cambiado (una version anterior)
function empty_page() {
    local dir=$1 page face=""
    [ "$DRY" -eq 1 ] && return 0
    page=$(mktemp) || return 1
    [ -n "$FONT_GOLDMAN_B64" ] && face="@font-face{font-family:Goldman;src:url(data:font/ttf;base64,$(tr -d ' \n' <<< "$FONT_GOLDMAN_B64")) format('truetype')}"
    cat > "$page" << HTML
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sin proyecto · Nexum Dev Stack</title>
<link rel="icon" href="data:image/png;base64,$(tr -d ' \n' <<< "$ICON_PNG_B64")">
<style>$face
body{font-family:system-ui,-apple-system,sans-serif;background:#1e1e1e;color:#ddd;display:flex;align-items:center;
justify-content:center;min-height:100vh;margin:0;padding:16px;box-sizing:border-box}main{text-align:center;max-width:34em}
img{width:120px;height:120px}.marca{font-size:2.2em;margin:18px 0 34px;white-space:nowrap}
.nexum{font-family:Goldman,system-ui,sans-serif;letter-spacing:2px;color:#fff}.stack{color:#62a0ea;margin-left:.3em}
h1{font-size:1.4em;font-weight:500;margin:0 0 10px}p{color:#9a9a9a;line-height:1.5;margin:0}b{color:#ddd;font-weight:600}</style>
</head><body><main>
<img src="data:image/png;base64,$(tr -d ' \n' <<< "$ICON_PNG_B64")" alt="">
<div class="marca"><span class="nexum">NEXUM</span><span class="stack">Dev Stack</span></div>
<h1>No hay ningún proyecto cargado</h1>
<p>Abre <b>Nexum Dev Stack</b> y, en <b>Proyectos</b>, pulsa <b>Cargar</b> en el que quieras ver aquí.</p>
</main></body></html>
HTML
    chmod 644 "$page"
    cmp -s "$page" "$dir/index.html" || project_write "$page" "$dir/index.html"
    rm -f "$page"
}

# desmontar-proyecto: el vhost de los proyectos (web.local) deja de apuntar al proyecto cargado y
# apunta a una pagina que dice que no hay ninguno. El enlace sigue existiendo: si se borrara, el
# gestor ya no reconoceria el vhost y al cargar otro proyecto intentaria crearlo de nuevo. Los
# dominios falseados de una tienda PrestaShop dejan de estarlo (vuelven a llevar a la web real)
function unload_project() {
    local link sudo="" dir=$HTDOCS_DIR/$EMPTY_PROJECT page rc

    link=$(project_link)
    if [ -z "$link" ]; then
        echo "No hay ningun vhost de proyectos (como $PROJECT_VHOST): no hay nada que desmontar"

        return 1
    fi
    if [ "$(readlink "$HTDOCS_DIR/$link" | sed 's:/*$::')" == "$EMPTY_PROJECT" ]; then
        echo "No hay ningun proyecto cargado en $link"

        return 0
    fi
    # La contraseña antes de cambiar nada: cancelarla deja el proyecto cargado
    sudo_first || return 1
    if [ -L "$dir" ] || { [ -e "$dir" ] && [ ! -d "$dir" ]; }; then
        echo "$dir no es una carpeta: borrala o cambiale el nombre y vuelve a intentarlo"

        return 1
    fi
    [ -w "$HTDOCS_DIR" ] || sudo=$SUDO
    if [ ! -d "$dir" ]; then
        run $sudo mkdir -m 755 "$dir" || return 1
    fi
    empty_page "$dir"
    # Todo o nada (como al cargar): si un paso falla o se cancela la tarea, el enlace vuelve al proyecto
    LOAD_UNDO_LINK=$link LOAD_UNDO_TARGET=$(readlink "$HTDOCS_DIR/$link" 2> /dev/null)
    LOAD_UNDO_ACTIVE=$(active_name)
    [ "$DRY" -eq 0 ] && trap 'load_project_undo; exit 130' TERM INT HUP
    unload_project_steps "$link" "$sudo"
    rc=$?
    if [ $rc -ne 0 ] && [ "$DRY" -eq 0 ]; then
        load_project_undo
    fi
    trap - TERM INT HUP
    LOAD_UNDO_LINK=""
    return $rc
}

function unload_project_steps() {
    local link=$1 sudo=$2
    run $sudo rm "$HTDOCS_DIR/$link" || return 1
    run $sudo ln -s "$EMPTY_PROJECT/" "$HTDOCS_DIR/$link" || return 1
    # (sin dominios falseados: los de una tienda PrestaShop vuelven a llevar a la web real)
    hosts_fake cargar || return 1
    # Cada proceso de PHP recuerda a donde apuntaba el enlace (realpath_cache, 120 s)
    if [ -f "$LINK/xamppfiles/logs/httpd.pid" ]; then
        echo "Recargando Apache para que PHP deje de servir el proyecto..."
        run xampp_ctl reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi
    media_sync || echo "Aviso: $link sigue pidiendo a produccion las imagenes del proyecto anterior"
    echo "Proyecto desmontado: $link ya no apunta a ningun proyecto"
}

# borrar-proyecto <carpeta> [--bd <base> [--copia]]: borra un proyecto entero. Por orden, y si un paso
# falla no se sigue (la carpeta, lo ultimo): lo desmonta si es el cargado, lo borra de Docker (sus
# contenedores y su copia de la BBDD), borra su BBDD de la version activa si se pide (con --copia,
# antes un volcado en ~/nexum-backups; si la copia falla no se borra nada), quita sus vhosts y las lineas
# de sus dominios de /etc/hosts (un dominio real no se queda falseado), lo que el gestor recordaba de
# el y su carpeta de htdocs. Las BBDD de las otras versiones no se tocan
function delete_project() {
    local folder=${1%/} db="" backup="" dir conf slug vhosts copy domains
    shift 2> /dev/null
    while [ $# -gt 0 ]; do
        case $1 in
            --bd) [ -n "$2" ] || { echo "Falta el nombre de la base de --bd"; return 1; }; db=$2; shift 2 ;;
            --copia) backup=--copia; shift ;;
            *) echo "Opcion desconocida: $1"; return 1 ;;
        esac
    done
    if [ -z "$folder" ]; then
        echo "Uso: nexum borrar-proyecto <carpeta> [--bd <base> [--copia]]"

        return 1
    fi
    valid_project "$folder" || return 1
    if [ "$folder" == "$EMPTY_PROJECT" ] || [ "$folder" == "$PROJECT_VHOST" ] || [ "$folder" == "$(project_link)" ]; then
        echo "$folder no es un proyecto: es del gestor"

        return 1
    fi
    if [ -n "$db" ]; then
        db_valid_name "$db" || return 1
        db_connect || return $?
        db_exists "$db" || { echo "No hay ninguna base de datos $db en lampp-$DB_FOLDER: no se ha borrado nada"; return 1; }
    fi
    dir=$HTDOCS_DIR/$folder
    echo "Se borra el proyecto $folder ($dir)"
    # La contraseña antes de cambiar nada: cancelarla deja el proyecto como estaba
    sudo_first || return 1

    if [ "$(readlink "$HTDOCS_DIR/$(project_link)" 2> /dev/null | sed 's:/*$::')" == "$folder" ]; then
        echo "Es el proyecto cargado: se desmonta"
        unload_project || return 1
    fi
    for conf in "$DOCKER_DIR"/*/proyecto.conf; do
        [ -f "$conf" ] && grep -qxF "CARPETA=$folder" "$conf" || continue
        slug=$(basename "$(dirname "$conf")")
        echo "En Docker como $slug: se borra"
        if [ "$DRY" -eq 0 ] && ! docker_ready; then
            echo "Docker sin root no esta en marcha: arrancalo para borrar $slug (no se ha borrado nada mas)"

            return 1
        fi
        docker_action borrar "$slug" || return 1
    done
    if [ -n "$db" ]; then
        drop_database "$db" $backup || { echo "No se sigue: la carpeta y los vhosts de $folder no se han tocado"; return 1; }
    fi

    # Vhosts con su DocumentRoot en la carpeta (o dentro de ella) y los dominios que llevaban
    vhosts=$(realpath_f "$ACTIVE_VHOSTS")
    copy=$(mktemp "$LOG_DIR/vhosts-borrar-XXXXXX") || return 1
    domains=$(python3 -I - "$vhosts" "$copy" "$folder" << 'EOF'
import re, sys
src, dst, folder = sys.argv[1:4]
lines = open(src, encoding="utf-8", errors="surrogateescape", newline="").read().split("\n")
root = re.compile(r'^\s*DocumentRoot\s+"?[^"\s]*/htdocs/%s(/[^"\s]*)?"?\s*$' % re.escape(folder), re.I)
out, block, names = [], None, set()
for line in lines:
    if block is None:
        if re.match(r"^\s*<VirtualHost\b", line, re.I):
            block = [line]
        else:
            out.append(line)
        continue
    block.append(line)
    if re.match(r"^\s*</VirtualHost>", line, re.I):
        if any(root.match(l) for l in block):
            for l in block:
                w = l.split("#", 1)[0].split()
                if len(w) >= 2 and w[0].lower() in ("servername", "serveralias"):
                    names |= {n.lower().split(":")[0] for n in w[1:]}
            # (sin la linea en blanco que lo separaba del anterior)
            while out and not out[-1].strip():
                out.pop()
        else:
            out += block
        block = None
if block:
    out += block
with open(dst, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write("\n".join(out))
print(" ".join(sorted(names)))
EOF
) || { rm -f "$copy"; return 1; }
    if ! cmp -s "$copy" "$vhosts"; then
        echo "Vhosts de $folder: ${domains:-sin dominio}"
        edit_vhosts --aplicar "$copy" || { rm -f "$copy"; echo "No se sigue: la carpeta de $folder no se ha tocado"; return 1; }
    fi
    rm -f "$copy"
    if [ -n "$domains" ]; then
        # Las lineas de esos dominios (falseadas o comentadas); de una linea con otros, solo los suyos
        copy=$(mktemp "$LOG_DIR/hosts-borrar-XXXXXX") || return 1
        python3 -I - "$HOSTS_FILE" "$copy" "$domains" << 'EOF'
import re, sys
src, dst, names = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
rx = re.compile(r"^(\s*#*\s*)(127\.0\.0\.1|::1)(\s+)(.*?)\s*$")
out = []
for line in open(src).read().splitlines():
    m = rx.match(line)
    if m:
        body, sep, comment = m.group(4).partition("#")
        keep = [n for n in body.split() if n.lower() not in names]
        if len(keep) != len(body.split()):
            if not keep:
                continue
            line = m.group(1) + m.group(2) + m.group(3) + " ".join(keep) + (" " + sep + comment if sep else "")
    out.append(line)
open(dst, "w").write("\n".join(out) + "\n")
EOF
        if ! cmp -s "$copy" "$HOSTS_FILE"; then
            echo "Lineas de $HOSTS_FILE de: $domains"
            edit_hosts --aplicar "$copy" || { rm -f "$copy"; echo "No se sigue: la carpeta de $folder no se ha tocado"; return 1; }
        fi
        rm -f "$copy"
        [ "$DRY" -eq 1 ] || local_off si $domains
    fi

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] se olvida $folder en $PROJECTS_FILE y $REPO_PROJECTS_FILE y se borra $dir"

        return 0
    fi
    if [ -f "$PROJECTS_FILE" ]; then
        awk -v f="$folder" '{ split($0, a, "="); split(a[2], b, " ") } !(index($0, "=") && b[1] == f)' "$PROJECTS_FILE" > "$PROJECTS_FILE.tmp" \
            && mv -f "$PROJECTS_FILE.tmp" "$PROJECTS_FILE"
    fi
    if [ -f "$REPO_PROJECTS_FILE" ]; then
        grep -vxF -- "$folder" "$REPO_PROJECTS_FILE" > "$REPO_PROJECTS_FILE.tmp"
        mv -f "$REPO_PROJECTS_FILE.tmp" "$REPO_PROJECTS_FILE"
    fi
    echo "Borrando la carpeta $dir..."
    # Con tu usuario; lo que haya dejado Apache con otro (daemon), con sudo y sin salir de la carpeta
    # (rm no sigue enlaces; -x: un disco montado dentro no se toca)
    rm -rfx -- "$dir" 2> /dev/null
    if [ -e "$dir" ]; then
        [ "$(realpath_f "$dir")" == "$(realpath_f "$HTDOCS_DIR")/$folder" ] && [ ! -L "$dir" ] \
            && sudo rm -rfx -- "$dir"
    fi
    if [ -e "$dir" ]; then
        echo "No se ha podido borrar del todo $dir: borra a mano lo que queda"

        return 1
    fi
    echo "Proyecto $folder borrado"
}

