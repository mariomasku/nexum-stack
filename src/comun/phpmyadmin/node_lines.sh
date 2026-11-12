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

# Descarga Node <mayor> de nodejs.org en ~/.nexum/node y lo comprueba con su lista de sumas sha256
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

