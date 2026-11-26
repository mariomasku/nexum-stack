# Node de Nexum (los de NODE_DIR, que pone node_install: no los de nvm ni el del sistema): el mas nuevo
# de cada rama frente al ultimo de su rama en nodejs.org (el que instalaria node_install, de su lista de
# sumas). X|Node|instalada|nueva por cada rama con uno nuevo; E| si no se ha podido consultar
function node_outdated() {
    local d v major cur latest base=https://nodejs.org/dist tls=(--proto =https --tlsv1.2)
    declare -A best=()
    [ -d "$NODE_DIR" ] || return 0
    for d in "$NODE_DIR"/v*/; do
        v=$(basename "$d")
        [[ "$v" =~ ^v([0-9]+)\.[0-9]+\.[0-9]+$ ]] && [ -x "$d/bin/node" ] || continue
        major=${BASH_REMATCH[1]} v=${v#v}
        if [ -z "${best[$major]}" ] || [ "$(printf '%s\n%s\n' "${best[$major]}" "$v" | sort -V | tail -1)" == "$v" ]; then
            best[$major]=$v
        fi
    done
    [ -n "$TEST_DIR" ] && [ -n "$LVM_NODE_BASE" ] && { base=$LVM_NODE_BASE; tls=(); }
    for major in "${!best[@]}"; do
        cur=${best[$major]}
        latest=$(curl -q -fsSL "${tls[@]}" --max-time 10 "$base/latest-v$major.x/SHASUMS256.txt" 2> /dev/null \
            | grep -oE "node-v$major\.[0-9]+\.[0-9]+" | head -1)
        latest=${latest#node-v}
        if [ -z "$latest" ]; then
            echo "E|nodejs.org (Node $major)"
        elif [ "$latest" != "$cur" ] && [ "$(printf '%s\n%s\n' "$cur" "$latest" | sort -V | tail -1)" == "$latest" ]; then
            echo "X|Node|$cur|$latest"
        fi
    done
}

# Pone al dia cada rama de Node que diga node_outdated (node_install) y, si ha ido bien, quita de esa rama
# los anteriores que no esten en marcha (los proyectos de Node usan siempre el mas nuevo de su rama)
function node_update() {
    local line f major d fail=0
    while IFS= read -r line; do
        IFS='|' read -r -a f <<< "$line"
        [ "${f[0]}" == X ] || continue
        major=${f[3]%%.*}
        if ! node_install "$major"; then
            fail=1
            continue
        fi
        for d in "$NODE_DIR"/v"$major".*/; do
            d=${d%/}
            [ "$(basename "$d")" == "v${f[3]}" ] && continue
            [[ "$(basename "$d")" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
            pgrep -f "$d/bin/node" > /dev/null 2>&1 && { echo "Node ${d##*/v} sigue en marcha: se queda hasta que lo pares"; continue; }
            rm -rf "$d" && echo "Quitado el Node anterior (${d##*/v})"
        done
    done < <(node_outdated)
    return $fail
}

# La ultima version publicada de lo que esta version de Nexum pone con una fija (Mailpit, cloudflared, la
# estable de Nginx): la de su ultima publicacion en GitHub (sin la API, que tiene limites: la direccion a
# la que lleva releases/latest) o la lista de descargas de nginx.org. Sin respuesta: nada
function upstream_latest() {
    local url tag
    case $1 in
        Mailpit) url=https://github.com/axllent/mailpit/releases/latest ;;
        cloudflared) url=https://github.com/cloudflare/cloudflared/releases/latest ;;
        Nginx)
            # (la estable: la rama par mas nueva)
            curl -q --proto =https -fsS --max-time 8 https://nginx.org/en/download.html 2> /dev/null \
                | grep -oE 'nginx-1\.[0-9]*[02468]\.[0-9]+\.tar\.gz' | sed -E 's/^nginx-//; s/\.tar\.gz$//' | sort -uV | tail -1
            return 0 ;;
        *) return 1 ;;
    esac
    tag=$(curl -q --proto =https -fsSI --max-time 8 "$url" 2> /dev/null | tr -d '\r' \
        | sed -n 's|^[Ll]ocation: .*/releases/tag/v\{0,1\}||p' | head -1)
    [[ "$tag" =~ ^[0-9]+(\.[0-9]+)+$ ]] && echo "$tag"
    return 0
}

# N|programa|la que pone Nexum|la publicada: de Mailpit, cloudflared y Nginx (solo los instalados), si se ha
# publicado una mas nueva que la que pone esta version de Nexum. Solo para saberlo: no cuenta como parche
# ni se instala (se pone la fijada, comprobada por su huella, hasta que la traiga una version de Nexum).
# Las tres consultas a la vez, como mucho unos segundos
function components_upstream() {
    local tmp prog pinned latest
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/nexum-publicadas.XXXXXX") || return 0
    mailpit_installed && { upstream_latest Mailpit > "$tmp/Mailpit" & }
    tunnel_installed && { upstream_latest cloudflared > "$tmp/cloudflared" & }
    nginx_installed && { upstream_latest Nginx > "$tmp/Nginx" & }
    wait
    for prog in Mailpit cloudflared Nginx; do
        [ -s "$tmp/$prog" ] || continue
        case $prog in Mailpit) pinned=$MAILPIT_VERSION ;; cloudflared) pinned=$TUNNEL_VERSION ;; Nginx) pinned=$NGINX_VERSION ;; esac
        latest=$(head -1 "$tmp/$prog")
        [ -n "$pinned" ] && [ "$latest" != "$pinned" ] && [ "$(printf '%s\n%s\n' "$pinned" "$latest" | sort -V | tail -1)" == "$latest" ] \
            && echo "N|$prog|$pinned|$latest"
    done
    rm -rf "$tmp"
    return 0
}
