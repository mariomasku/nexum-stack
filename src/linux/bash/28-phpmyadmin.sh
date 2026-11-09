# ===========================================================================
# phpMyAdmin: actualizar el de una version
# ===========================================================================
# phpMyAdmin que admite cada PHP: la 5.2 (la ultima) desde PHP 7.2.5, la 5.1.4 desde la 7.1.3 y la
# 4.9.11 antes. Los XAMPP traen la 4.9.2, 5.2.0 o 5.2.1, con fallos de seguridad corregidos despues.
function pma_for_php() {
    local php=$1
    if [ "$(printf '%s\n%s\n' 7.2.5 "$php" | sort -V | head -1)" == 7.2.5 ]; then
        latest_pma
    elif [ "$(printf '%s\n%s\n' 7.1.3 "$php" | sort -V | head -1)" == 7.1.3 ]; then
        echo 5.1.4
    else
        echo 4.9.11
    fi
}

# Huella sha256 del phpMyAdmin <version>: las que pone el gestor van fijadas aqui; otra, la que
# publica phpMyAdmin (del mismo servidor que el fichero: solo protege de descargas a medias)
function pma_sum() {
    case $1 in
        5.2.3) echo 57881348297c4412f86c410547cf76b4d8a236574dd2c6b7d6a2beebe7fc44e3 ;;
        5.1.4) echo 3230cf0e004b6284c70e0cb26064a8666b271749ef54236d035104a972822999 ;;
        4.9.11) echo 2b14737a2220e5ac9d2eaf683df6b56ebaa490d038ee980367cb4db909a57923 ;;
        *) curl -q --proto =https --proto-redir =https -fsSL "https://files.phpmyadmin.net/phpMyAdmin/$1/phpMyAdmin-$1-all-languages.tar.xz.sha256" 2> /dev/null | grep -oE '^[0-9a-f]{64}' ;;
    esac
}

# Version de phpMyAdmin instalada en <carpeta de phpmyadmin> (vacio si no se sabe)
function pma_installed() {
    local v
    v=$(grep -hoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$1/libraries/classes/Version.php" \
        "$1/libraries/classes/Config.php" "$1/libraries/Config.php" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")
    [ -z "$v" ] && v=$(grep -rhoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$1/libraries" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")
    echo "$v"
}

# actualizar-phpmyadmin <version>: pone el phpMyAdmin mas nuevo que admite su PHP (comprobado con su
# sha256), con la configuracion de antes (config.inc.php) y una clave de cookies nueva si la de
# XAMPP es la de fabrica. El anterior queda en phpmyadmin.anterior.
function update_pma() {
    local FETCH_FRESH=1
    local version=$1 root dir php cur want tmp sum new grp d rc=0
    if [ "$version" == "--todas" ]; then
        for d in $(lampp_dirs); do
            [ -f "$d/phpmyadmin/config.inc.php" ] || continue
            update_pma "${d#/opt/lampp-}" || rc=1
        done
        return $rc
    fi
    valid_version_name "$version" && [ -d "/opt/lampp-$version" ] \
        || { echo "No existe la version $version de lampp en el sistema"; return 1; }
    root="/opt/lampp-$version"
    dir=$root/phpmyadmin
    if [ ! -f "$dir/config.inc.php" ]; then
        echo "$version no tiene phpMyAdmin con su configuracion ($dir/config.inc.php)"
        return 1
    fi
    php=$(php_version "$root")
    cur=$(pma_installed "$dir")
    want=$(pma_for_php "$php")
    [[ "$want" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "No se ha podido saber que phpMyAdmin poner"; return 1; }
    if [ -n "$cur" ] && [ "$(printf '%s\n%s\n' "$want" "$cur" | sort -V | tail -1)" == "$cur" ]; then
        echo "phpMyAdmin de $version ya esta al dia ($cur, PHP $php)"
        return 0
    fi
    task_plan "Actualizando phpMyAdmin de $version" "Descargar y comprobar phpMyAdmin $want" "Preparar su configuración" "Cambiar la carpeta"
    echo "phpMyAdmin de $version: ${cur:-version antigua} -> $want (PHP $php)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] descarga, comprobacion sha256 y cambio de $dir (el anterior en phpmyadmin.anterior)"
        return 0
    fi
    # Antes de cambiar nada como root: la carpeta de la version tiene que ser de root (y en
    # Linux, /opt tambien), no un enlace que lleve a otro sitio
    vhosts_root > /dev/null
    if [ -L "$root" ] || [ -L "$dir" ] || [ "$(stat -c %u /opt)" != 0 ] || [ "$(stat -c %u "$root")" != 0 ]; then
        echo "No se cambia phpMyAdmin: /opt o $root no son del administrador (lvm-instalador asegurar --todas)"
        return 1
    fi
    task_step
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-pma.XXXXXX") || return 1
    sum=$(pma_sum "$want")
    if ! download_signed "https://files.phpmyadmin.net/phpMyAdmin/$want/phpMyAdmin-$want-all-languages.tar.xz" "$tmp/pma.tar.xz" "$sum" "$GPG_FPR_PMA" \
            || ! tar -xJf "$tmp/pma.tar.xz" -C "$tmp"; then
        rm -rf "$tmp"
        return 1
    fi
    new=$tmp/phpMyAdmin-$want-all-languages
    [ -d "$new" ] || { rm -rf "$tmp"; echo "El paquete de phpMyAdmin no es el esperado"; return 1; }
    # La configuracion de antes; la clave de las cookies de XAMPP es la misma en todos (xampp)
    task_step
    cp "$dir/config.inc.php" "$new/config.inc.php" || { rm -rf "$tmp"; return 1; }
    python3 -I - "$new/config.inc.php" <<'PY'
import re, secrets, string, sys
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="surrogateescape").read()
m = re.search(r"""\$cfg\[\s*['"]blowfish_secret['"]\s*\]\s*=\s*(['"])(.*?)\1""", text)
if m is None or len(m.group(2)) < 32:
    key = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))
    assign = "$cfg['blowfish_secret'] = '%s'" % key
    if m:
        text = text[:m.start()] + assign + text[m.end():]
    else:
        text = text.rstrip() + "\n" + assign + "; /* lvm-instalador */\n"
    open(path, "w", encoding="utf-8", errors="surrogateescape").write(text)
PY
    grp=$(stat -c %G "$dir/tmp" 2> /dev/null || echo root)
    # phpMyAdmin no trae enlaces: uno en la carpeta (que es tuya hasta que root la copia) seria de
    # otro programa. Se mira otra vez en la copia, ya de root, y tmp la crea root vacia (si fuera un
    # enlace, root cambiaria el dueño y los permisos de lo que apunta)
    if [ -n "$(find "$new" \( -type l -o -type f -links +1 \) -print -quit)" ]; then
        rm -rf "$tmp"
        echo "El phpMyAdmin descargado tiene enlaces (no deberia): no se cambia nada"
        return 1
    fi
    task_step
    if ! { sudo rm -rf "$root/phpmyadmin.anterior" && sudo mv "$dir" "$root/phpmyadmin.anterior"; }; then
        echo "No se ha podido apartar $dir: no se cambia nada"
        rm -rf "$tmp"
        return 1
    fi
    if ! { sudo cp -R "$new" "$dir" \
            && [ -z "$(sudo find "$dir" -type l -print -quit)" ] \
            && sudo chown -R root:root "$dir" \
            && sudo chmod -R go-w "$dir" \
            && sudo rm -rf "$dir/tmp" \
            && sudo install -d -o 0 -g "$grp" -m 775 "$dir/tmp"; }; then
        sudo rm -rf "$dir" && sudo mv "$root/phpmyadmin.anterior" "$dir"
        echo "No se ha podido cambiar $dir: se ha dejado el phpMyAdmin anterior"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    if [ "$(active_dir)" == "/opt/lampp-$version" ] && [ -f /opt/lampp/logs/httpd.pid ]; then
        run sudo /opt/lampp/lampp reloadapache > /dev/null
    fi
    echo "phpMyAdmin $want instalado en $version"
}

# Proyectos de Node (Astro, Next, Nuxt, SvelteKit, Vite...): carpetas de htdocs con su package.json, cada
# una con su propio servidor en 127.0.0.1, siempre con tu usuario (nunca root ni sudo). En Desarrollo, con
# el servidor del proyecto; Compilado, como en produccion: es el unico que se comparte por el tunel, porque
# el proxy no deja pasar ficheros ocultos (/node_modules/.vite) y asi el codigo fuente no sale del equipo.
NODE_DIR=$LOG_DIR/node
NODE_RUN_DIR=$NODE_DIR/proyectos
NODE_DEFAULT_MAJOR=26
NODE_PORT_FROM=4321
NODE_PORT_TO=4399

# P|carpeta|tipo|parado o marcha|modo|direccion|Node que pide (26, o 24+ si vale de ahi en adelante)|
# dependencias instaladas (1/0)|scripts (d de dev, b de build, s de start). Con una carpeta, solo esa.
# No son de Node las webs de PHP que usan npm para sus estilos (wp-config.php, index.php, artisan)
NODE_LIST_PY='
import json, os, re, subprocess, sys
htdocs, run = sys.argv[1:3]
only = sys.argv[3] if len(sys.argv) > 3 else None
KINDS = (("astro", "Astro"), ("next", "Next"), ("nuxt", "Nuxt"), ("@sveltejs/kit", "SvelteKit"), ("vite", "Vite"))


def need(d, pkg):
    for name in (".nvmrc", ".node-version"):
        try:
            with open(os.path.join(d, name), encoding="utf-8") as f:
                m = re.match(r"v?(\d+)", f.read(40).strip())
        except (OSError, UnicodeError):
            m = None
        if m:
            return m.group(1)
    engines = pkg.get("engines")
    text = str(engines.get("node") or "") if isinstance(engines, dict) else ""
    m = re.search(r"\d+", text)
    if not m:
        return ""
    return m.group(0) + ("+" if text.strip().startswith(">") else "")


def running(name):
    conf = {}
    try:
        with open(os.path.join(run, name + ".conf"), encoding="utf-8") as f:
            for line in f:
                k, _, v = line.rstrip("\n").partition("=")
                conf[k] = v
        out = subprocess.run(["ps", "-o", "lstart=", "-p", conf["PID"]], capture_output=True, text=True,
                             env={"LC_ALL": "C", "PATH": "/usr/bin:/bin"}, timeout=5).stdout.strip()
    except (OSError, KeyError, ValueError, subprocess.SubprocessError):
        return None
    return conf if out and out == conf.get("LSTART") else None


try:
    names = [only] if only else sorted(os.listdir(htdocs), key=str.lower)
except OSError:
    names = []
for name in names:
    d = os.path.join(htdocs, name)
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9 ._-]*", name) or os.path.islink(d):
        continue
    if any(os.path.exists(os.path.join(d, f)) for f in ("wp-config.php", "index.php", "artisan")):
        continue
    try:
        with open(os.path.join(d, "package.json"), encoding="utf-8") as f:
            pkg = json.load(f)
    except (OSError, ValueError):
        continue
    if not isinstance(pkg, dict):
        continue
    deps = {}
    for key in ("dependencies", "devDependencies"):
        if isinstance(pkg.get(key), dict):
            deps.update(pkg[key])
    scripts = pkg.get("scripts") if isinstance(pkg.get("scripts"), dict) else {}
    kind = next((label for dep, label in KINDS if dep in deps), "")
    if not kind and not ("dev" in scripts or "start" in scripts):
        continue
    conf = running(name)
    print("|".join(("P", name, kind or "Node", "marcha" if conf else "parado", conf.get("MODE", "") if conf else "",
                    "http://127.0.0.1:%s" % conf["PORT"] if conf and conf.get("PORT", "").isdigit() else "",
                    need(d, pkg), "1" if os.path.isdir(os.path.join(d, "node_modules")) else "0",
                    ("d" if "dev" in scripts else "") + ("b" if "build" in scripts else "") + ("s" if "start" in scripts else ""))))
'

function node_lines() {
    python3 -I -c "$NODE_LIST_PY" "$HTDOCS_DIR" "$NODE_RUN_DIR" "$@"
}

function gui_node() {
    node_lines | tr -d '\000-\011\013-\037'
}

# La carpeta bin de un Node que valga para lo que pide el proyecto (26, 24+ o nada: el mas nuevo de los
# que coincidan). De Nexum, de nvm o el del sistema; los nuevos, primero.
function node_find() {
    local want=$1 min=${1%+} d v major key best="" best_key=-1 sys
    for d in "$NODE_DIR"/v*/bin "$HOME"/.nvm/versions/node/v*/bin; do
        [ -x "$d/node" ] && [ -x "$d/npm" ] || continue
        v=$(basename "$(dirname "$d")")
        [[ "$v" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || continue
        major=${BASH_REMATCH[1]}
        key=$(( major * 1000000 + BASH_REMATCH[2] * 1000 + BASH_REMATCH[3] ))
        if [ -n "$want" ]; then
            if [[ "$want" == *+ ]]; then [ "$major" -ge "$min" ] || continue; else [ "$major" -eq "$min" ] || continue; fi
        fi
        [ "$key" -gt "$best_key" ] && { best=$d; best_key=$key; }
    done
    if [ -z "$best" ]; then
        sys=$(command -v node 2> /dev/null)
        if [ -n "$sys" ] && [ -x "$(dirname "$sys")/npm" ]; then
            major=$("$sys" -v 2> /dev/null | sed -E 's/^v([0-9]+).*/\1/')
            if [[ "$major" =~ ^[0-9]+$ ]] && { [ -z "$want" ] \
                    || { [[ "$want" == *+ ]] && [ "$major" -ge "$min" ]; } || [ "$major" -eq "${min:-0}" ]; }; then
                best=$(dirname "$sys")
            fi
        fi
    fi
    [ -n "$best" ] && echo "$best"
}

# Descarga Node <mayor> de nodejs.org en ~/.lvm-instalador/node y lo comprueba con su lista de sumas sha256
function node_install() {
    local major=$1 base=https://nodejs.org/dist os arch sums name sha got tmp top version tls=(--proto =https --tlsv1.2)
    [[ "$major" =~ ^[0-9]+$ ]] || { echo "Versión de Node no válida: $major"; return 1; }
    case "$(uname -s)" in
        Darwin) os=darwin ;;
        Linux) os=linux ;;
        *) echo "Sistema sin Node descargable: $(uname -s)"; return 1 ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) arch=arm64 ;;
        x86_64|amd64) arch=x64 ;;
        *) echo "Procesador sin Node descargable: $(uname -m)"; return 1 ;;
    esac
    # (en las pruebas, de una carpeta local)
    [ -n "$TEST_DIR" ] && [ -n "$LVM_NODE_BASE" ] && { base=$LVM_NODE_BASE; tls=(); }
    echo "Descargando Node $major de nodejs.org ($os, $arch)..."
    mkdir -p -m 700 "$NODE_DIR" || return 1
    tmp=$(mktemp -d "$NODE_DIR/descarga.XXXXXX") || return 1
    if ! sums=$(curl -q -fsSL "${tls[@]}" --retry 2 --max-time 60 "$base/latest-v$major.x/SHASUMS256.txt"); then
        rm -rf "$tmp"
        echo "No se ha podido leer la lista de Node $major en nodejs.org"
        return 1
    fi
    name=$(awk -v rx="^node-v$major\\\\.[0-9]+\\\\.[0-9]+-$os-$arch\\\\.tar\\\\.gz$" '$2 ~ rx { print $2; exit }' <<< "$sums")
    sha=$(awk -v n="$name" '$2 == n { print $1; exit }' <<< "$sums")
    if [ -z "$name" ] || [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
        rm -rf "$tmp"
        echo "Node $major no tiene paquete para $os $arch"
        return 1
    fi
    if ! curl -q -fsSL "${tls[@]}" --retry 2 --max-time 900 -o "$tmp/node.tar.gz" "$base/latest-v$major.x/$name"; then
        rm -rf "$tmp"
        echo "No se ha podido descargar $name"
        return 1
    fi
    if command -v sha256sum > /dev/null; then got=$(sha256sum "$tmp/node.tar.gz" | cut -d' ' -f1); else got=$(shasum -a 256 "$tmp/node.tar.gz" | cut -d' ' -f1); fi
    if [ "$got" != "$sha" ]; then
        rm -rf "$tmp"
        echo "La descarga de Node no coincide con su suma sha256 (${got:-ninguna}): no se instala."
        return 1
    fi
    top=${name%.tar.gz}
    version=${top#node-}
    version=${version%%-*}
    if ! tar -xzf "$tmp/node.tar.gz" -C "$tmp" "$top" 2> /dev/null || [ ! -x "$tmp/$top/bin/node" ]; then
        rm -rf "$tmp"
        echo "El paquete de Node no trae su programa: no se instala."
        return 1
    fi
    rm -rf "${NODE_DIR:?}/$version"
    mv "$tmp/$top" "$NODE_DIR/$version" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    echo "Node $version instalado en $NODE_DIR"
}

# El pid del servidor de un proyecto, si sigue siendo aquel (misma hora de arranque)
function node_pid() {
    local conf=$NODE_RUN_DIR/$1.conf pid start
    [ -f "$conf" ] || return 1
    pid=$(sed -n 's/^PID=//p' "$conf")
    start=$(sed -n 's/^LSTART=//p' "$conf")
    [[ "$pid" =~ ^[0-9]+$ ]] && [ -n "$start" ] || return 1
    [ "$(LC_ALL=C ps -o lstart= -p "$pid" 2> /dev/null | sed -E 's/^ +//; s/ +$//')" == "$start" ] || return 1
    echo "$pid"
}

function node_free_port() {
    python3 -I -c '
import socket, sys
for port in range(int(sys.argv[1]), int(sys.argv[2]) + 1):
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", port))
    except OSError:
        continue
    finally:
        s.close()
    print(port)
    break
' "$NODE_PORT_FROM" "$NODE_PORT_TO"
}

# Instala lo que le falte: lo pide su fichero de bloqueo. Los scripts de sus paquetes se ejecutan con tu usuario
function node_deps() {
    local dir=$1 bin=$2 lock=""
    shift 2
    for lock in package-lock.json pnpm-lock.yaml yarn.lock; do
        [ -f "$dir/$lock" ] && break
        lock=""
    done
    if [ -d "$dir/node_modules" ] && { [ -z "$lock" ] || [ ! "$dir/$lock" -nt "$dir/node_modules" ]; }; then
        echo "Dependencias: ya están instaladas"
        return 0
    fi
    echo "Instalando las dependencias..."
    case "$lock" in
        package-lock.json) ( cd "$dir" && /usr/bin/env -i "$@" "$bin/npm" ci --no-audit --no-fund ) ;;
        pnpm-lock.yaml) ( cd "$dir" && /usr/bin/env -i "$@" "$bin/npx" --yes pnpm install --frozen-lockfile ) ;;
        yarn.lock) ( cd "$dir" && /usr/bin/env -i "$@" "$bin/npx" --yes yarn install --frozen-lockfile ) ;;
        *) ( cd "$dir" && /usr/bin/env -i "$@" "$bin/npm" install --no-audit --no-fund ) ;;
    esac || { echo "No se han podido instalar las dependencias"; return 1; }
    touch "$dir/node_modules"
}

# Astro con un adaptador de un alojamiento (Vercel, Netlify, Cloudflare) no se puede servir en este equipo:
# se compila con el de Node, sin tocar su configuracion ni su package.json (todo dentro de node_modules)
function node_build_astro() {
    local dir=$1 bin=$2 conf="" c
    shift 2
    for c in astro.config.mjs astro.config.ts astro.config.mts astro.config.js astro.config.cjs; do
        [ -f "$dir/$c" ] && { conf=$c; break; }
    done
    if [ -z "$conf" ] || ! grep -qE "@astrojs/(vercel|netlify|cloudflare)" "$dir/$conf"; then
        ( cd "$dir" && /usr/bin/env -i "$@" "$bin/npx" --no-install astro build )
        return
    fi
    if [ ! -f "$dir/node_modules/@astrojs/node/package.json" ]; then
        if [ -f "$dir/pnpm-lock.yaml" ] || [ -f "$dir/yarn.lock" ]; then
            echo "Este proyecto usa un adaptador de alojamiento: añade @astrojs/node a sus dependencias para compilarlo aquí."
            return 1
        fi
        ( cd "$dir" && /usr/bin/env -i "$@" "$bin/npm" install --no-save --no-audit --no-fund @astrojs/node ) || return 1
    fi
    printf "import base from '../%s';\nimport node from '@astrojs/node';\nexport default { ...base, adapter: node({ mode: 'standalone' }) };\n" "$conf" \
        > "$dir/node_modules/.nexum-astro.config.mjs" || return 1
    echo "(compilando con @astrojs/node en lugar de su adaptador de alojamiento; el proyecto no cambia)"
    ( cd "$dir" && /usr/bin/env -i "$@" "$bin/npx" --no-install astro build --config node_modules/.nexum-astro.config.mjs )
}

# Lo que deja el servidor en marcha, en NODE_CMD: node_command <carpeta> <tipo> <modo> <scripts> <bin> <puerto>
NODE_CMD=()
function node_command() {
    local dir=$1 kind=$2 mode=$3 scripts=$4 bin=$5 port=$6 root
    NODE_CMD=()
    if [ "$mode" == desarrollo ]; then
        case "$kind" in
            Astro) NODE_CMD=("$bin/npx" --no-install astro dev --host 127.0.0.1 --port "$port") ;;
            Next) NODE_CMD=("$bin/npx" --no-install next dev -H 127.0.0.1 -p "$port") ;;
            Nuxt) NODE_CMD=("$bin/npx" --no-install nuxt dev --host 127.0.0.1 --port "$port") ;;
            SvelteKit|Vite) NODE_CMD=("$bin/npx" --no-install vite --host 127.0.0.1 --port "$port" --strictPort) ;;
            *) if [[ "$scripts" == *d* ]]; then NODE_CMD=("$bin/npm" run dev); elif [[ "$scripts" == *s* ]]; then NODE_CMD=("$bin/npm" start); fi ;;
        esac
    else
        case "$kind" in
            Astro)
                if [ -f "$dir/dist/server/entry.mjs" ]; then
                    NODE_CMD=("$bin/node" dist/server/entry.mjs)
                else
                    root=dist
                    [ -d "$dir/dist/client" ] && root=dist/client
                    NODE_CMD=(python3 -I -m http.server --bind 127.0.0.1 --directory "$root" "$port")
                fi
                ;;
            Next) NODE_CMD=("$bin/npx" --no-install next start -H 127.0.0.1 -p "$port") ;;
            Nuxt) NODE_CMD=("$bin/node" .output/server/index.mjs) ;;
            SvelteKit|Vite) NODE_CMD=("$bin/npx" --no-install vite preview --host 127.0.0.1 --port "$port" --strictPort) ;;
            *) [[ "$scripts" == *s* ]] && NODE_CMD=("$bin/npm" start) ;;
        esac
    fi
    [ "${#NODE_CMD[@]}" -gt 0 ]
}

# node-arrancar <carpeta> [desarrollo|compilado]
function node_start() {
    local folder=${1%/} mode=${2:-desarrollo} dir line kind state need deps scripts bin port log conf pid n x steps=() e=()
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        echo "Los proyectos de Node no se arrancan como root."
        return 1
    fi
    [[ "$mode" =~ ^(desarrollo|compilado)$ ]] || { echo "El modo es desarrollo o compilado"; return 1; }
    valid_project "$folder" || return 1
    dir=$HTDOCS_DIR/$folder
    line=$(node_lines "$folder")
    if [ -z "$line" ]; then
        echo "$folder no es un proyecto de Node"
        return 1
    fi
    IFS='|' read -r x x kind state x x need deps scripts <<< "$line"
    if [ "$mode" == compilado ] && [ "$kind" == Node ] && [[ "$scripts" != *s* ]]; then
        echo "$folder no tiene un script start: no se sabe cómo servirlo compilado"
        return 1
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $folder ($kind, $mode): Node ${need:-el que haya}, dependencias y servidor en 127.0.0.1"
        return 0
    fi
    steps=("Preparar Node ${need:-}" "Instalar las dependencias")
    [ "$mode" == compilado ] && steps+=("Compilar el proyecto")
    steps+=("Arrancar el servidor")
    task_plan "Arrancando $folder" "${steps[@]}"
    [ "$state" == marcha ] && node_stop "$folder" > /dev/null

    task_step
    bin=$(node_find "$need")
    if [ -z "$bin" ]; then
        x=${need%+}
        node_install "${x:-$NODE_DEFAULT_MAJOR}" || return 1
        bin=$(node_find "$need")
        [ -n "$bin" ] || { echo "No se encuentra el Node recién instalado"; return 1; }
    fi
    echo "Node $("$bin/node" -v) ($bin)"
    port=$(node_free_port)
    [ -n "$port" ] || { echo "No hay ningún puerto libre entre $NODE_PORT_FROM y $NODE_PORT_TO"; return 1; }
    e=("HOME=$HOME" "USER=${USER:-$(id -un)}" "LANG=${LANG:-es_ES.UTF-8}" "TERM=dumb" "CI=1"
       "PATH=$bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" "HOST=127.0.0.1" "PORT=$port" "NO_COLOR=1"
       "ASTRO_TELEMETRY_DISABLED=1" "NEXT_TELEMETRY_DISABLED=1")

    task_step
    node_deps "$dir" "$bin" "${e[@]}" || return 1

    if [ "$mode" == compilado ]; then
        task_step
        echo "Compilando..."
        if [ "$kind" == Astro ]; then
            node_build_astro "$dir" "$bin" "${e[@]}"
        elif [[ "$scripts" == *b* ]]; then
            ( cd "$dir" && /usr/bin/env -i "${e[@]}" "$bin/npm" run build )
        fi || { echo "No se ha podido compilar $folder"; return 1; }
    fi

    task_step
    node_command "$dir" "$kind" "$mode" "$scripts" "$bin" "$port" || { echo "$folder no tiene un script dev ni start"; return 1; }
    mkdir -p -m 700 "$NODE_RUN_DIR" || return 1
    log=$NODE_RUN_DIR/$folder.log conf=$NODE_RUN_DIR/$folder.conf
    : > "$log" && chmod 600 "$log" || return 1
    # (en su propia sesion, para pararlo con todos sus hijos y que siga al cerrar la ventana)
    ( cd "$dir" && exec python3 -I -c 'import os, sys
os.setsid()
os.execv("/usr/bin/env", ["env", "-i"] + sys.argv[1:])' "${e[@]}" "${NODE_CMD[@]}" >> "$log" 2>&1 < /dev/null ) &
    pid=$!
    ( umask 077; printf 'PID=%s\nLSTART=%s\nPORT=%s\nMODE=%s\n' "$pid" \
        "$(LC_ALL=C ps -o lstart= -p "$pid" 2> /dev/null | sed -E 's/^ +//; s/ +$//')" "$port" "$mode" > "$conf" ) || return 1
    echo "Arrancando el servidor en http://127.0.0.1:$port ..."
    for n in $(seq 360); do
        if ! kill -0 "$pid" 2> /dev/null; then
            rm -f "$conf"
            echo "El servidor de $folder se ha parado al arrancar. Lo último que ha dicho:"
            tail -20 "$log" | sed 's/^/  /'
            return 1
        fi
        curl -q -s -o /dev/null --noproxy '*' --max-time 2 "http://127.0.0.1:$port/" && break
        sleep 0.5
    done
    if [ "$n" -ge 360 ]; then
        node_stop "$folder" > /dev/null
        echo "El servidor de $folder no responde en http://127.0.0.1:$port tras 3 minutos: se para. Lo último que ha dicho:"
        tail -20 "$log" | sed 's/^/  /'
        return 1
    fi
    echo "$folder en marcha ($mode): http://127.0.0.1:$port"
    echo "URL|http://127.0.0.1:$port"
}

# node-parar <carpeta>: el servidor con todos sus hijos y, si se esta compartiendo, tambien su tunel (ese
# puerto podria acabar siendo de otro proyecto)
function node_stop() {
    local folder=${1%/} pid conf=$NODE_RUN_DIR/${1%/}.conf port n
    [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]] || { echo "Carpeta no válida: $folder"; return 1; }
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] se para $folder"
        return 0
    fi
    pid=$(node_pid "$folder")
    if [ -z "$pid" ]; then
        rm -f "$conf"
        echo "$folder no está en marcha"
        return 0
    fi
    port=$(sed -n 's/^PORT=//p' "$conf")
    if [[ "$port" =~ ^[0-9]+$ ]] && [ -f "$TUNNEL_STATE" ] && grep -qF "\"target\": \"http://127.0.0.1:$port\"" "$TUNNEL_STATE"; then
        tunnel_close > /dev/null
        echo "Túnel cerrado: compartía este proyecto"
    fi
    kill -TERM -- "-$pid" 2> /dev/null
    for n in $(seq 20); do
        kill -0 -- "-$pid" 2> /dev/null || break
        sleep 0.25
    done
    kill -KILL -- "-$pid" 2> /dev/null
    rm -f "$conf"
    echo "$folder parado"
}

# node-registro <carpeta>: lo ultimo que ha dicho su servidor
function node_log() {
    local folder=${1%/} log=$NODE_RUN_DIR/${1%/}.log
    [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]] || { echo "Carpeta no válida: $folder"; return 1; }
    if [ -f "$log" ]; then
        tail -300 "$log"
    else
        echo "$folder aún no ha arrancado desde aquí"
    fi
}

# Tareas de la ventana (LVM_TAREA=1): lo que cambia algo pide la contraseña de administrador antes de
# empezar, no a mitad. Si se cancela, no se ha hecho nada (antes, lo hecho hasta el primer sudo se
# quedaba: el enlace de un proyecto al desmontarlo, por ejemplo). Lo que nunca la necesita, sin pedirla
if [ "${LVM_TAREA:-}" == 1 ]; then
    case "$1" in
        gui-*|node-*|exportar-bd|descargar-bd|docker-registros|construir-pila|version|--version|-v|acerca|about|novedades|procesos) ;;
        *) sudo_first || exit 130 ;;
    esac
fi

case "$1" in
    "")
        # Abierto desde un acceso del menu de una version anterior (1.8 o antes abrian el panel en
        # GNOME Terminal, y GNOME puede seguir lanzando esa orden de su cache aunque el acceso ya
        # este al dia): si hay ventana, se abre la ventana y se cierra la terminal
        if [ "$DRY" -eq 0 ] && [ "$(ps -o sid= -p $$ 2> /dev/null | tr -d ' ')" == "$$" ] \
            && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; } && gui_available; then
            update_launchers
            setsid "$SELF" ventana < /dev/null > /dev/null 2>&1 &
            exit 0
        fi
        panel
        ;;
    instalar|instalador|install|panel)
        shift
        if [ $# -eq 0 ]; then
            offer_command_install
            panel_install
            [ "$UI" == "whiptail" ] && clear
        else
            cli_install "$@"
        fi
        ;;
    use) use_lampp "$2" ;;
    list) list_lampp ;;
    list-db) list_databases ;;
    status|estado) echo -e "$(status_text)" ;;
    disable) disable_lampp ;;
    remove|desinstalar) cli_remove "$2" "$3" ;;
    ventana|gui|ventana-nueva) gui_open ;;
    arrancar|start) control_lampp start ;;
    parar|stop) control_lampp stop ;;
    reiniciar|restart) control_lampp restart ;;
    gui-datos) gui_data ;;
    gui-vuelta) gui_round ;;
    gui-paquete) gui_package ;;
    gui-ramas) gui_branches ;;
    gui-fechas) gui_php_dates ;;
    gui-docker) gui_docker ;;
    docker-instalar) docker_install ;;
    docker-crear) shift; docker_create "$@" ;;
    docker-arrancar|docker-parar|docker-registros|docker-borrar) docker_action "${1#docker-}" "$2" ;;
    docker-nuevo) shift; docker_web_create "$@" ;;
    docker-php-anadir) docker_web_add "$2" "$3" ;;
    docker-php-añadir) docker_web_add "$2" "$3" ;;
    docker-php-quitar) docker_web_remove "$2" "$3" ;;
    docker-php-elegir) docker_web_switch "$2" "$3" ;;
    docker-pasar) docker_pass "$2" ;;
    docker-parar-todo) docker_stop_all ;;
    docker-web) shift; docker_web_command "$@" ;;
    tunel) tunnel_status ;;
    tunel-instalar) tunnel_install ;;
    tunel-abrir) shift; tunnel_open "$@" ;;
    tunel-cerrar) tunnel_close ;;
    node-arrancar) shift; node_start "$@" ;;
    node-parar) node_stop "$2" ;;
    node-registro) node_log "$2" ;;
    gui-node) gui_node ;;
    docker-php) docker_set_php "$2" "$3" ;;
    docker-usuario-pruebas) docker_test_admin "$2" ;;
    docker-imagen) docker_update_image "$2" ;;
    docker-contenedor) docker_container_action "$2" "$3" ;;
    docker-imagenes) docker_image_action "$2" "$3" ;;
    docker-volumen-borrar) docker_volume_remove "$2" ;;
    gui-docker-estadisticas) gui_docker_stats ;;
    gui-bbdd-tamanos) gui_db_sizes ;;
    gui-proyectos-tamanos) gui_project_sizes "$2" ;;
    gui-parches) gui_patches "$2" ;;
    gui-al-dia) gui_up_to_date "$2" ;;
    gui-crear-acceso) write_launcher ;;
    gui-bd-comprobar) gui_db_check ;;
    importar-bd) import_database "$2" "$3" "${@:4}" ;;
    crear-bd) create_database "$2" ;;
    borrar-bd) drop_database "$2" "$3" ;;
    exportar-bd|descargar-bd) export_database "$2" "$3" "$4" ;;
    copiar-bd) shift; copy_database "$@" ;;
    gui-bd-info) gui_db_info "$2" ;;
    gui-proyectos) gui_projects ;;
    vincular-bd) link_database "$2" "$3" "$4" ;;
    actualizar-proyecto) shift; project_update "$@" ;;
    gui-proyecto-git) gui_project_git "$2" ;;
    cargar-proyecto) load_project "$2" "$3" "$4" ;;
    desmontar-proyecto) unload_project ;;
    borrar-proyecto) shift; delete_project "$@" ;;
    usuario-pruebas) test_admin "$2" "$3" ;;
    montar-proyecto) mount_project "$2" "$3" "$4" "$5" "$6" ;;
    vaciar-cache)
        if [ "$2" == "--bd" ]; then ps_clear_cache_db "$3"; else ps_clear_cache "$2"; fi
        ;;
    wp-config) wp_config "$2" "$3" ;;
    gui-hosts) gui_hosts ;;
    gui-servicios) gui_services ;;
    servicio) service_control "$2" "$3" ;;
    asegurar) secure_command "$2" ;;
    construir-pila)
        # (solo lo lanza install_stack, con sudo -u nexum-build: las variables, en un fichero de root)
        if [ "$(id -un)" != "$BUILD_USER" ] || [ ! -f "$2" ] || [ "$(stat -c %u "$2")" != 0 ]; then
            echo "construir-pila solo lo usa install_stack"
            exit 1
        fi
        . "$2"
        cd "$build" || exit 1
        function stack_fail() { stack_child_fail; }
        STEP_LOG="" STEP_DESC=""
        stack_build_phase
        ;;
    barrera-web|barrera-webs) cross_site_command "$2" ;;
    correo) mail_command "$2" "$3" ;;
    reparar-bd-sistema) repair_db_system ;;
    arreglar-certificados) fix_certs ;;
    confiar-certificados) browser_trust "$2" ;;
    actualizar-phpmyadmin) update_pma "$2" ;;
    cerrar-procesos) close_processes "$2" ;;
    procesos) lampp_processes | awk -F'|' '{ printf "%-8s %-8s %-12s %-10s %s\n", $2, $3, $4, ($5 == "?" ? "anterior" : $5), $7 ($6 == 1 ? "  <- sobra" : "") }' ;;
    hosts-falsear) hosts_fake_one "$2" "$3" ;;
    media-produccion) media_proxy "$2" "$3" ;;
    media-proyecto) media_project "$2" "$3" ;;
    gui-wp-produccion) gui_wp_prod "$2" ;;
    ps-imagenes) ps_images "$2" "$3" ;;
    hosts-enlace) hosts_fix_link ;;
    nuevo-dominio) new_custom_domain "$2" "$3" "$4" ;;
    vhosts|editar-vhosts) edit_vhosts "$2" ;;
    hosts|editar-hosts) edit_hosts "$2" "$3" ;;
    add) register_lampp "$2" ;;
    add-php) UI=text; install_plan "php:$2" ;;
    rehacer|actualizar) cli_rebuild "$2" ;;
    github) shift; github_command "$@" ;;
    github-conectar) github_connect "$2" ;;
    github-desconectar) github_disconnect ;;
    repos) shift; repos_list "$@" ;;
    repo-traer) repo_fetch "$2" "$3" ;;
    docker-bd) docker_db_mode "$2" "$3" "$4" ;;
    docker-reposo) shift; docker_idle_command "$@" ;;
    componentes) components_check "$2" ;;
    componentes-actualizar) components_update ;;
    actualizar-a) upgrade_to "$2" "$3" ;;
    add-xampp) ( install_xampp "$2" ) ;;
    version|--version|-v) echo "$APP_NAME $APP_VERSION" ;;
    acerca|about) echo -e "$(about_text)" ;;
    novedades) changes_text ;;
    -h|--help|--ayuda) sed -n '3,/^$/p' "$SELF" | sed 's/^# \{0,1\}//' ;;
    *) echo "Accion desconocida: $1 (usa --ayuda)"; exit 1 ;;
esac
