# El token de la sesion de gh, sin esperar mas de 15 s (con el llavero bloqueado o sin el, gh se queda
# esperandolo)
function gh_token() {
    local out pid
    out=$(mktemp "${TMPDIR:-/tmp}/lvm-gh.XXXXXX") || return 1
    gh auth token > "$out" 2> /dev/null < /dev/null &
    pid=$!
    # (el vigilante, con su salida a /dev/null: si no, $(gh_token) espera a que acabe su sleep, 15 s en
    # cada llamada aunque gh conteste al momento; y se lleva su sleep al acabar)
    ( sleep 15 & s=$!; trap 'kill $s 2> /dev/null; exit 0' TERM; wait $s; kill $pid 2> /dev/null ) > /dev/null 2>&1 &
    wait $pid 2> /dev/null
    kill $! 2> /dev/null
    cat "$out"
    rm -f "$out"
}

# GET a la API de GitHub: github_api <ruta o direccion> [fichero para las cabeceras]. El token, por la
# entrada de curl (-K -): en la linea de ordenes se veria con ps
function github_api() {
    local url=$1 hdr=${2:-/dev/null} token
    token=$(github_token)
    [ -n "$token" ] || return 2
    [[ "$url" == https://api.github.com/* ]] || url=https://api.github.com$url
    printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -q --proto =https --proto-redir =https -fsS --max-time 30 -K - \
        -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" -H "User-Agent: nexum-dev-stack" \
        -D "$hdr" "$url"
}

