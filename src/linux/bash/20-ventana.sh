# ===========================================================================
# Ventana (interfaz grafica con GTK 3)
# ===========================================================================

# La ventana es un programa en Python (GTK 3 y Python 3.8: funciona desde Ubuntu 20.04 sin instalar
# nada) que va dentro de este archivo, en gui_source. "nexum ventana" lo escribe en
# ~/.lvm-instalador/ventana.py y lo abre. La ventana no repite la logica del instalador: llama a
# este script con los comandos gui-* (datos en lineas "TIPO|campo|...") y con los de siempre (use,
# instalar, actualizar, desinstalar...) dentro de una pseudoterminal, para que sudo funcione igual
# que en la terminal. La contraseña la pide la ventana.
GUI_FILE="$LOG_DIR/ventana.py"
# Identificador de la ventana (el dock la relaciona con el acceso por StartupWMClass)
GUI_APP_ID="dev.hexer.LamppVersionManager"

function gui_available() {
    python3 -I -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' 2> /dev/null
}

# Para la ventana: N|version|fecha|sha256|ruta del paquete .deb de nexum mas nuevo que esta
# version, y avisos (I|texto). Se busca en la ultima publicacion del repositorio de GitHub (su .deb
# y su firma se descargan a UPDATES_DIR) y en la carpeta de descargas (el Centro de aplicaciones no
# ofrece actualizar un .deb suelto). Solo cuando se pide (Buscar actualizaciones): se instala como
# root, y cualquier web puede dejar un fichero en Descargas. Solo vale un paquete tuyo, sin enlaces,
# firmado con la clave de UPDATE_KEY_FPR (su .sig al lado) y que solo lleve los ficheros de
# nexum, de root y con sus permisos (755 o 644).
UPDATES_DIR="$LOG_DIR/actualizaciones"
PACKAGE_FILES_PY='
import posixpath, sys, tarfile
files = {"opt/nexum/nexum.sh", "opt/nexum/nexum-actualizar",
         "opt/nexum/nexum-stack-firma.gpg",
         "usr/share/applications/nexum.desktop",
         "usr/share/icons/hicolor/256x256/apps/nexum.png",
         "usr/share/polkit-1/actions/io.github.mariomasku.nexum.policy"}
dirs = {""}
for f in files:
    parts = f.split("/")
    for i in range(1, len(parts)):
        dirs.add("/".join(parts[:i]))
try:
    with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as tar:
        for m in tar:
            name = (m.name[2:] if m.name.startswith("./") else m.name).rstrip("/")
            name = "" if name == "." else name
            if name.startswith("/") or ".." in name.split("/"):
                sys.exit(1)
            if not ((m.isdir() and name in dirs) or (m.isreg() and name in files)):
                sys.exit(1)
            exe = name in ("opt/nexum/nexum.sh", "opt/nexum/nexum-actualizar")
            if m.uid != 0 or m.gid != 0 or m.uname not in ("root", "") or m.gname not in ("root", "") or (m.mode & 0o7777) != (0o755 if m.isdir() or exe else 0o644):
                sys.exit(1)
except tarfile.TarError:
    sys.exit(1)
'
# Ultima publicacion de GitHub (JSON de la API en la entrada): version|fecha|url del .deb|url del
# .sig. Sin borradores ni versiones de prueba, y las descargas solo de esa publicacion
RELEASE_PY='
import json, re, sys
repo = sys.argv[1]
try:
    r = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
if not isinstance(r, dict) or not isinstance(r.get("assets"), list):
    sys.exit(1)
tag = r.get("tag_name") or ""
m = re.fullmatch(r"v([0-9]{1,4}(\.[0-9]{1,4}){1,3})", tag)
when = r.get("published_at") or ""
if not m or r.get("draft") or r.get("prerelease") or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", when):
    sys.exit(1)
deb = "nexum_%s_all.deb" % m.group(1)
base = "https://github.com/%s/releases/download/%s/" % (repo, tag)
urls = {a.get("name"): a.get("browser_download_url") for a in r["assets"] if isinstance(a, dict)}
if urls.get(deb) != base + deb or urls.get(deb + ".sig") != base + deb + ".sig":
    sys.exit(1)
print("%s|%s|%s|%s" % (m.group(1), when, base + deb, base + deb + ".sig"))
'

# ¿Esta <paquete> firmado con la clave de las actualizaciones? (la firma, en <paquete>.sig)
function update_signed() {
    local dir status=""

    [ -f "$1.sig" ] && [ ! -L "$1.sig" ] && command -v gpgv > /dev/null || return 1
    dir=$(mktemp -d) || return 1
    base64 -d <<< "$UPDATE_KEY_B64" > "$dir/firma.gpg" 2> /dev/null \
        && status=$(GNUPGHOME=$dir gpgv --status-fd 1 --keyring "$dir/firma.gpg" "$1.sig" "$1" 2> /dev/null)
    rm -rf "$dir"

    grep -q "^\[GNUPG:\] VALIDSIG $UPDATE_KEY_FPR " <<< "$status"
}

# Si la ultima publicacion de GitHub es mas nueva que esta version, descarga su .deb y su firma a
# UPDATES_DIR (solo tuya; el .deb con la fecha de la publicacion). Si no se puede, lo dice (I|...)
function github_update() {
    local json code rel v when deb_url sig_url f
    local get=(curl -q --proto =https --proto-redir =https -fsSL --max-time 60)

    # (sin -f: un 404 es que aun no hay ninguna publicacion, no un fallo de la conexion)
    json=$(curl -q --proto =https --proto-redir =https -sSL --max-time 30 --max-filesize 1048576 \
        -H "Accept: application/vnd.github+json" -w '\n%{http_code}' \
        "https://api.github.com/repos/$UPDATE_REPO/releases/latest" 2> /dev/null)
    code=${json##*$'\n'} json=${json%$'\n'*}
    case "$code" in
        200) ;;
        404) echo "I|Todavía no hay ninguna versión publicada en GitHub"; return 0 ;;
        *) echo "I|No se ha podido consultar GitHub (¿sin conexión?): solo se ha buscado en Descargas"; return 0 ;;
    esac
    rel=$(python3 -I -c "$RELEASE_PY" "$UPDATE_REPO" <<< "$json") \
        || { echo "I|La última publicación de GitHub no trae un paquete de Nexum Dev Stack con su firma"; return 0; }
    IFS='|' read -r v when deb_url sig_url <<< "$rel"
    dpkg --compare-versions "$v" gt "$APP_VERSION" || return 0

    [ -L "$UPDATES_DIR" ] && { echo "I|$UPDATES_DIR es un enlace: no se descarga nada ahí"; return 0; }
    mkdir -p -m 700 "$UPDATES_DIR" && chmod 700 "$UPDATES_DIR" || return 0
    f=$UPDATES_DIR/nexum_${v}_all.deb
    # Ya descargada y bien firmada: no se vuelve a bajar
    update_signed "$f" && return 0
    rm -f -- "$UPDATES_DIR"/nexum_* "$UPDATES_DIR"/lvm-instalador_*
    if ! "${get[@]}" --max-filesize 52428800 -o "$f.part" "$deb_url" 2> /dev/null \
            || ! "${get[@]}" --max-filesize 65536 -o "$f.sig" "$sig_url" 2> /dev/null; then
        rm -f -- "$f.part" "$f.sig"
        echo "I|No se ha podido descargar la $v de GitHub"
        return 0
    fi
    mv -f -- "$f.part" "$f"
    touch -d "$when" "$f" 2> /dev/null
    if ! update_signed "$f"; then
        rm -f -- "$f" "$f.sig"
        echo "I|La $v de GitHub no está firmada por quien hace el programa: no se ofrece"
    fi

    return 0
}

function gui_package() {
    local dir f v best="" best_v=$APP_VERSION real unsigned=""

    command -v dpkg-deb > /dev/null || return 0
    github_update
    for dir in "$UPDATES_DIR" "$(xdg-user-dir DOWNLOAD 2> /dev/null)" "$HOME/Descargas" "$HOME/Downloads"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/nexum_*_all.deb; do
            [ -f "$f" ] && [ ! -L "$f" ] && [ -O "$f" ] || continue
            [ "$(dpkg-deb -f "$f" Package 2> /dev/null)" == "nexum" ] || continue
            # Solo los ficheros de nexum, normales (sin enlaces ni especiales), y firmado:
            # lo mismo que comprueba como root nexum-actualizar antes de instalarlo
            dpkg-deb --fsys-tarfile "$f" 2> /dev/null | python3 -I -c "$PACKAGE_FILES_PY" || continue
            v=$(dpkg-deb -f "$f" Version 2> /dev/null)
            [ -n "$v" ] && dpkg --compare-versions "$v" gt "$best_v" || continue
            if update_signed "$f"; then
                best=$f best_v=$v
            else
                unsigned=$f
            fi
        done
    done
    # Uno sin firma (hecho en este equipo con empaquetar-deb.sh, por ejemplo) solo en la terminal
    [ -z "$best" ] && [ -n "$unsigned" ] \
        && echo "I|$(basename "$unsigned") no lleva la firma de quien publica el programa. Si es tuyo, instálalo en la terminal: sudo apt install $unsigned"
    if [ -n "$best" ]; then
        real=$(readlink -f "$best")
        echo "N|$best_v|$(date -r "$real" '+%d/%m/%Y %H:%M')|$(sha256sum "$real" | cut -d' ' -f1)|$real"
    fi

    return 0
}

function gui_open() {
    if ! gui_available; then
        echo "La ventana necesita GTK 3 para Python. Instalalo con: sudo apt install python3-gi gir1.2-gtk-3.0"
        echo "Mientras tanto puedes usar el panel de la terminal: nexum"

        return 1
    fi

    if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        echo "No hay sesion grafica. Usa el panel de la terminal: nexum"

        return 1
    fi

    mkdir -p -m 700 "$LOG_DIR"
    # El codigo de la ventana va por la entrada de python, sin fichero en tu carpeta que otro
    # programa pudiera cambiar entre que se escribe y se abre (el ventana.py de antes se borra)
    rm -f "$GUI_FILE" "$GUI_FILE.tmp"
    cmp -s "$ICON_FILE" <(base64 -d <<< "$ICON_PNG_B64" 2> /dev/null) || install_icon
    [ "$DRY" -eq 0 ] && update_launchers
    # La pagina de web.local sin proyecto, al dia tras una actualizacion (solo si se puede escribir
    # sin contraseña: si no, al desmontar el proximo proyecto)
    [ -w "$HTDOCS_DIR/$EMPTY_PROJECT/index.html" ] && empty_page "$HTDOCS_DIR/$EMPTY_PROJECT" > /dev/null 2>&1

    # Abierta desde el menu no hay terminal donde ver los errores: van a ventana.log (vacio al abrirla y en
    # modo de añadir: si Limpieza lo vacia con la ventana abierta, sigue escribiendo al principio)
    [ -t 2 ] || { : > "$LOG_DIR/ventana.log"; exec 2>> "$LOG_DIR/ventana.log"; }
    # Con su ruta: el PATH de la sesion puede llevar delante carpetas tuyas (~/.local/bin)
    LVM_SIMULAR=$DRY exec /usr/bin/python3 -I - "$SELF" < <(gui_source)
}

# Datos de la ventana:
#   M|nombre|version|firma
#   A|activa|en marcha (1/0)|/opt/lampp sin registrar (1/0)|binarios x86_64 (1/0)|acceso del menu (1/0)
#   V|carpeta|php|apache|mariadb|proftpd|perl|phpmyadmin|tipo|bases de|motivo para no desinstalar
#   D|carpeta|base de datos|fecha|tipo (i: importada con nexum, c: ultimo cambio de tablas)
#   Z|procesos de LAMPP que sobran en memoria (de otras versiones)
#   Y|version montada|bytes del registro de errores: sus tablas del sistema de MariaDB son antiguas
#   R|carpeta|ok, parche o vulnerable|texto     PHP2Shell en cada version (php2shell_state)
# gui-vuelta: lo que la ventana pregunta cada 20 s (gui-datos, gui-hosts, gui-servicios y gui-proyectos) en
# una sola orden: el script se lee una vez y no cuatro (unos 200 ms cada una). Cada parte, en su subshell
# (un exit no corta las demas), va detras de una linea «@@<orden>|<codigo de salida>»
function gui_round() {
    local part out rc
    for part in gui-datos:gui_data gui-hosts:gui_hosts gui-servicios:gui_services gui-proyectos:gui_projects; do
        out=$("${part#*:}" 2>&1 < /dev/null)
        rc=$?
        echo "@@${part%%:*}|$rc"
        [ -n "$out" ] && printf '%s\n' "$out"
    done
    return 0
}

function gui_data() {
    local active=$(active_dir) dir name owner blocker kind dates=()

    echo "M|$APP_NAME|$APP_VERSION|$SIGNATURE"
    echo "A|${active#/opt/lampp-}|$(lampp_running && echo 1 || echo 0)|$([ -e /opt/lampp ] && [ ! -L /opt/lampp ] && echo 1 || echo 0)|$(native_binaries && echo 1 || echo 0)|$(launcher_exists && echo 1 || echo 0)"
    echo "H|$ACTIVE_VHOSTS|$HOSTS_FILE"
    # Correo de pruebas: E|Mailpit instalado (1/0)|encendido (1/0)|modo de WordPress|Mailpit en marcha
    # (1/0)|version instalada|direccion de su web|version que instala el gestor. Si la version activa
    # esta en marcha y Mailpit no (se ha cerrado la sesion, por ejemplo), se arranca
    [ "$DRY" -eq 0 ] && mailpit_sync --suave > /dev/null 2>&1
    echo "E|$(mailpit_installed && echo 1 || echo 0)|$(mail_on && echo 1 || echo 0)|$(mail_wp_mode)|$([ -n "$(mailpit_pid)" ] && echo 1 || echo 0)|$(mailpit_installed_version)|$MAIL_UI_URL|$MAILPIT_VERSION"
    # Procesos de LAMPP en memoria que no son de la version montada
    local stray=$(stray_summary)
    [ -n "$stray" ] && echo "Z|$stray"
    # Vhosts de proyectos cuya carpeta ya no esta en htdocs: W|carpeta|dominios (Apache avisa de cada uno al
    # arrancar)
    local vh
    vh=$(readlink -f "$ACTIVE_VHOSTS" 2> /dev/null)
    [ -n "$vh" ] && [ -f "$vh" ] && python3 -I -c "$VHOSTS_ORPHANS_PY" "$vh" "$HTDOCS_DIR" lista 2> /dev/null
    # Servicios de la version montada a los que se puede entrar desde otros equipos de la red
    local exposed=$(exposed_summary)
    [ -n "$exposed" ] && echo "N|$exposed"
    # Versiones que, si se arrancan a mano, quedarian abiertas a la red (o con el FTP de fabrica)
    local open_versions=$(unsecured_versions)
    [ -n "$open_versions" ] && echo "U|$open_versions"
    # Tablas del sistema de MariaDB antiguas en la version montada (llenan su registro de errores)
    if db_system_outdated; then
        local err_log=$(db_error_log "$active")
        echo "Y|${active#/opt/lampp-}|$([ -n "$err_log" ] && stat -c %s "$err_log" 2> /dev/null || echo 0)"
    fi
    # Certificados de proyectos en los que confia todo el equipo: C|dominio|motivo y A|CA
    # y G|dominio: proyectos https cuyo certificado propio aun no acepta el navegador, y Q|dominio:
    # los que acepta y ya no deberia (una tienda que ya no esta falseada)
    cert_audit | awk -F'|' '$1 == "C" { print "C|" $2 "|" $5 } $1 == "A" && !seen[$2]++ { print "W|" $2 }
        $1 == "T" && $5 == "0" { print "G|" $2 } $1 == "U" && !gone[$2]++ { print "Q|" $2 }
        $1 == "S" { n = split($2, a, "/"); print "C|" a[n] " (sin usar)|sistema" }'

    for dir in $(lampp_dirs); do
        name=${dir#/opt/lampp-}
        kind=XAMPP
        is_fpm_install "$dir" && kind=sobre
        is_stack_install "$dir" && kind=propia
        owner=$(data_owner "$dir")
        owner=${owner:-$name}
        blocker=$(remove_blocker "$name")
        blocker=${blocker//\\n/ }
        local fields=$(stack_fields "$dir")
        echo "V|$name|$fields|$kind|$owner|${blocker//|/ }"
        echo "R|$name|$(php2shell_state "$dir" "${fields%%|*}")"
        dates+=("$name" "/opt/lampp-$owner/var/mysql")
    done
    # (las fechas de las BBDD de todas las versiones en un solo python3)
    [ ${#dates[@]} -gt 0 ] && db_dates --varias "${dates[@]}"
    return 0
}

# Ramas de PHP para instalar (consulta php.net):
#   B|rama|ultimo parche|con soporte (1/0)|MariaDB|Perl|estado|carpeta|estado en php.net|fin del soporte
#     activo|fin de los parches de seguridad (de php_branch_states; vacios si no se pudo consultar)
#     estado: nueva (se instala en lampp-<carpeta>), instalada (en lampp-<carpeta>),
#     existe (ya hay otra cosa en esa carpeta)
#     ... |fecha del ultimo parche (AAAA-MM-DD)|seguridad (1 si php.net lo marca como parche de seguridad)
#   X|carpeta|release|php|instalado (1/0)          (catalogo de XAMPP, solo en equipos x86_64)
function gui_branches() {
    local releases=$(php_releases) supported=$(php_supported) branch latest have folder state sup b
    local states=$(php_branch_states) st all=$(php_all_releases) date sec

    if [ -z "$releases" ]; then
        echo "ERROR|No se ha podido consultar php.net. Comprueba la conexion a internet."

        return 1
    fi

    while read -r branch latest; do
        read -r -a b <<< "$(stack_branches "$branch")"
        sup=0
        grep -qxF "$branch" <<< "$supported" && sup=1
        have=$(php_installed_in "$latest")
        if [ -n "$have" ]; then
            state=instalada folder=${have#/opt/lampp-}
        else
            folder=$(item_folder "$(php_item "$latest" "$latest")")
            state=nueva
            [ -e "${TEST_DIR:-/opt}/lampp-$folder" ] && state=existe
        fi
        st=$(grep "^$branch|" <<< "$states" | cut -d'|' -f2-)
        # (siempre tres campos, aunque no se haya podido consultar: van despues la fecha y la marca)
        [ -z "$st" ] && st="||"
        read -r _ date sec <<< "$(awk -v v="$latest" '$1 == v {print; exit}' <<< "$all")"
        [ "$sec" == "seguridad" ] && sec=1 || sec=0
        echo "B|$branch|$latest|$sup|${b[1]}|${b[3]}|$state|$folder|$st|${date:--}|$sec"
    done <<< "$releases"

    if native_binaries; then
        local entry release php
        for entry in "${XAMPP_CATALOG[@]}"; do
            IFS='|' read -r folder release php _ <<< "$entry"
            echo "X|$folder|$release|$php|$([ -e "/opt/lampp-$folder" ] && echo 1 || echo 0)"
        done
    fi
}

# Fecha de publicacion en php.net del PHP de cada version instalada: F|carpeta|php|AAAA-MM-DD
function gui_php_dates() {
    local all=$(php_all_releases) dir php date
    [ -n "$all" ] || return 1
    for dir in $(lampp_dirs); do
        php=$(stack_fields "$dir" | cut -d'|' -f1)
        [[ "$php" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        date=$(awk -v v="$php" '$1 == v { print $2; exit }' <<< "$all")
        [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && echo "F|${dir#/opt/lampp-}|$php|$date"
    done
    return 0
}

