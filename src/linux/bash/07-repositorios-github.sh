# ===========================================================================
# Repositorios de GitHub (pestaña Repositorios)
# ===========================================================================
# Los repositorios de una organizacion o cuenta de GitHub, para clonarlos por SSH en htdocs (o, si ya
# estan, traer sus cambios con git pull). Como DevHub: un token de GitHub (o la sesion de gh) solo para
# leer la lista, y los prefijos de los nombres que se ven (dob-wordpress-, dob-prestashop-...). El token
# va en el llavero de la sesión, no en un fichero; GITHUB_CONF_FILE (solo tuyo) lleva:
#   CUENTA=   la organizacion o cuenta cuyos repositorios se ven
#   PREFIJOS= los prefijos de los nombres que se ven, separados por espacios (vacio: todos)
#   ORIGEN=   llavero (el token guardado) o gh (la sesion de la herramienta de GitHub)
GITHUB_CONF_FILE=$HOME/.lvm-instalador/github
GITHUB_KEYRING_SERVICE=nexum-dev-stack
GITHUB_DEFAULT_PREFIXES="dob-wordpress- dob-prestashop-"

function github_conf() {
    local v="" p ok=""
    [ -f "$GITHUB_CONF_FILE" ] && v=$(sed -n "s/^$1=//p" "$GITHUB_CONF_FILE" | head -1)
    case $1 in
        CUENTA) [[ "$v" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]] || v="" ;;
        ORIGEN) [[ "$v" =~ ^(llavero|gh)$ ]] || v="" ;;
        PREFIJOS)
            grep -q '^PREFIJOS=' "$GITHUB_CONF_FILE" 2> /dev/null || v=$GITHUB_DEFAULT_PREFIXES
            for p in $v; do [[ "$p" =~ ^[A-Za-z0-9._-]{1,50}$ ]] && ok+=" $p"; done
            v=${ok# } ;;
    esac
    echo "$v"
}

# github_conf_set <clave> <valor>
function github_conf_set() {
    local tmp
    mkdir -p -m 700 "$(dirname "$GITHUB_CONF_FILE")" || return 1
    tmp=$(mktemp "$GITHUB_CONF_FILE.XXXXXX") || return 1
    { grep -v "^$1=" "$GITHUB_CONF_FILE" 2> /dev/null; printf '%s=%s\n' "$1" "$2"; } > "$tmp" && chmod 600 "$tmp" \
        && mv -f "$tmp" "$GITHUB_CONF_FILE"
}

# El token con el que se lee la lista (nada si no hay)
function github_token() {
    case $(github_conf ORIGEN) in
        llavero) timeout 15 secret-tool lookup service "$GITHUB_KEYRING_SERVICE" account github 2> /dev/null ;;
        gh) command -v gh > /dev/null && gh_token ;;
    esac
}

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

# github-conectar [--gh]: con el token que llega por la entrada (una linea), o con la sesion de gh.
# Se comprueba con GitHub antes de guardarlo
function github_connect() {
    local token login
    if [ "$1" == --gh ]; then
        command -v gh > /dev/null && token=$(gh_token)
        [ -n "$token" ] || { echo "No hay sesión de gh (gh auth login) en este equipo"; return 1; }
    else
        IFS= read -r token
        token=${token//[[:space:]]/}
        [[ "$token" =~ ^[A-Za-z0-9_]{20,255}$ ]] || { echo "Eso no parece un token de GitHub (ghp_…, github_pat_…)"; return 1; }
    fi
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] se comprobaria el token con GitHub y se guardaria en el llavero de la sesión"; return 0; }
    login=$(printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -q --proto =https -fsS --max-time 30 -K - \
        -H "Accept: application/vnd.github+json" -H "User-Agent: nexum-dev-stack" https://api.github.com/user 2> /dev/null \
        | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["login"])' 2> /dev/null)
    [ -n "$login" ] || { echo "GitHub no acepta ese token (¿caducado o sin permiso?)"; return 1; }
    if [ "$1" == --gh ]; then
        github_conf_set ORIGEN gh || return 1
    else
    command -v secret-tool > /dev/null || { echo "Hace falta secret-tool para guardar el token en el llavero: sudo apt install libsecret-tools"; return 1; }
    # (al llavero de la sesion por la entrada de secret-tool: en la linea de ordenes se veria con ps)
    printf '%s' "$token" | secret-tool store --label="Nexum Dev Stack (GitHub)" service "$GITHUB_KEYRING_SERVICE" account github \
        || { echo "No se ha podido guardar el token en el llavero de la sesion"; return 1; }
        github_conf_set ORIGEN llavero || return 1
    fi
    [ -n "$(github_conf CUENTA)" ] || github_conf_set CUENTA "$login"
    echo "Conectado a GitHub como $login"
}

function github_disconnect() {
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] se quitaria el token de el llavero de la sesión"; return 0; }
    command -v secret-tool > /dev/null && secret-tool clear service "$GITHUB_KEYRING_SERVICE" account github 2> /dev/null
    github_conf_set ORIGEN ""
    echo "Desconectado de GitHub (el token ya no está en el llavero de la sesión)"
}

# github [estado]: G|conectado (1/0)|usuario|origen|cuenta|prefijos
# github cuenta <organizacion o cuenta> | prefijos "<p1> <p2>..."
function github_command() {
    local login=""
    case $1 in
        ""|estado)
            [ -n "$(github_token)" ] && login=$(github_api /user 2> /dev/null | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["login"])' 2> /dev/null)
            echo "G|$([ -n "$login" ] && echo 1 || echo 0)|$login|$(github_conf ORIGEN)|$(github_conf CUENTA)|$(github_conf PREFIJOS)" ;;
        cuenta)
            # (tambien su direccion de GitHub o con @: https://github.com/hexer-dev, @hexer-dev)
            local a kind
            a=$(printf "%s" "$2" | sed "s/^[[:space:]]*//; s/[[:space:]]*$//")
            a=${a#http://} a=${a#https://} a=${a#www.} a=${a#github.com/} a=${a#@} a=${a%%/*}
            [[ "$a" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]] || { echo "«$2» no es un nombre de organización o cuenta de GitHub (letras, números y -, como hexer-dev)"; return 1; }
            # (con la conexion hecha, que exista)
            if [ -n "$(github_token)" ]; then
                kind=$(github_api "/users/$a" 2> /dev/null | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["type"])' 2> /dev/null)
                [ -n "$kind" ] || { echo "En GitHub no hay ninguna organización ni cuenta $a (o el token no la ve)"; return 1; }
            fi
            github_conf_set CUENTA "$a" && echo "Repositorios de $a" ;;
        prefijos)
            local p ok=""
            for p in $2; do
                [[ "$p" =~ ^[A-Za-z0-9._-]{1,50}$ ]] || { echo "Prefijo no válido: $p (letras sin acentos, números, punto, _ y -)"; return 1; }
                ok+=" $p"
            done
            github_conf_set PREFIJOS "${ok# }" && echo "Prefijos: ${ok# }" ;;
        *) echo "Uso: lvm-instalador github [estado] | cuenta <nombre> | prefijos \"<p1> <p2>\""; return 1 ;;
    esac
}

# Proyectos de htdocs que son un clon de un repositorio de GitHub: "dueño/repositorio carpeta" (en
# minusculas el nombre, que GitHub no distingue). Su origin, por https o por SSH
function repo_clones() {
    python3 -I - "$HTDOCS_DIR" << 'EOF'
import os, re, sys
base = sys.argv[1]
for name in sorted(os.listdir(base)):
    cfg = os.path.join(base, name, ".git", "config")
    if os.path.islink(os.path.join(base, name)) or not os.path.isfile(cfg):
        continue
    try:
        text = open(cfg, encoding="utf-8", errors="replace").read(200000)
    except OSError:
        continue
    m = re.search(r'\[remote "origin"\][^\[]*?\burl\s*=\s*(\S+)', text)
    if not m:
        continue
    r = re.match(r"(?:https://(?:[^@/]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._][A-Za-z0-9._-]*?)(?:\.git)?/?$", m.group(1))
    if r:
        print(r.group(1).lower(), name)
EOF
}

# repos [--todos] [--cache]: los repositorios de la cuenta (sin los archivados; sin --todos, solo los de
# los prefijos), los mas recientes primero. Lo que da GitHub se guarda en REPOS_CACHE_FILE (solo tuyo):
# con --cache, la lista de la ultima vez, sin preguntar a GitHub (al abrir la pestaña, al momento):
#   C|usuario conectado|cuenta|Organization o User|cuantos|cuantos se ven
#   R|dueño/repo|nombre|privado (1/0)|ultimo cambio (AAAA-MM-DD)|rama|prefijo|web|descripcion|estado|carpeta
#     estado: clonado (en la carpeta), ocupado (hay una carpeta con su nombre que no es ese repositorio) o nuevo
#   E|lo que ha fallado
REPOS_CACHE_FILE=$HOME/.lvm-instalador/repos-github
function repos_list() {
    local account kind login path all="" hdr page=1 url next clones show_all=0 cached=0 a
    for a in "$@"; do
        case $a in --todos) show_all=1 ;; --cache) cached=1 ;; esac
    done
    account=$(github_conf CUENTA)
    # (la lista de la ultima vez no necesita el token: con el llavero bloqueado se quedaria esperandolo)
    if [ $cached -eq 1 ]; then
        [ -n "$(github_conf ORIGEN)" ] || { echo "E|GitHub no está conectado (Configuración, GitHub)"; return 1; }
    elif [ -z "$(github_token)" ]; then
        echo "E|GitHub no está conectado (Configuración, GitHub)"
        return 1
    fi
    [ -n "$account" ] || { echo "E|Falta la organización o cuenta (Configuración, GitHub)"; return 1; }
    # (la primera linea de la cache: usuario, cuenta y tipo; si es de otra cuenta, no vale)
    if [ $cached -eq 1 ]; then
        IFS='|' read -r login a kind < "$REPOS_CACHE_FILE" 2> /dev/null
        [ -n "$login" ] && [ "${a,,}" == "${account,,}" ] || return 0
        all=$(tail -n +2 "$REPOS_CACHE_FILE")
        clones=$(repo_clones)
        repos_rows "$login" "$account" "$kind" "$show_all" "$clones" <<< "$all"
        return
    fi
    login=$(github_api /user 2> /dev/null | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["login"])' 2> /dev/null)
    [ -n "$login" ] || { echo "E|GitHub no acepta el token (¿caducado?): conéctalo de nuevo en Configuración"; return 1; }
    kind=$(github_api "/users/$account" 2> /dev/null | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["type"])' 2> /dev/null)
    [ -n "$kind" ] || { echo "E|No existe en GitHub la organización o cuenta $account"; return 1; }
    if [ "$kind" == Organization ]; then
        path="/orgs/$account/repos?type=all&sort=pushed&per_page=100"
    elif [ "${login,,}" == "${account,,}" ]; then
        # (la tuya: tambien los privados)
        path="/user/repos?affiliation=owner&sort=pushed&per_page=100"
    else
        path="/users/$account/repos?sort=pushed&per_page=100"
    fi
    hdr=$(mktemp "${TMPDIR:-/tmp}/lvm-github.XXXXXX") || return 1
    url=$path
    while [ -n "$url" ] && [ $page -le 30 ]; do
        all+=$(github_api "$url" "$hdr") || { rm -f "$hdr"; echo "E|GitHub no ha dado la lista de $account"; return 1; }
        all+=$'\n'
        next=$(tr -d '\r' < "$hdr" | sed -n 's/^[Ll]ink: .*<\([^>]*\)>; rel="next".*/\1/p' | head -1)
        url=$next page=$((page + 1))
    done
    rm -f "$hdr"
    # (con el numero del proceso: la lista se puede estar pidiendo a la vez al abrir y en la pestaña)
    ( umask 077; mkdir -p "$(dirname "$REPOS_CACHE_FILE")"; { echo "$login|$account|$kind"; printf '%s' "$all"; } > "$REPOS_CACHE_FILE.$$" \
        && mv -f "$REPOS_CACHE_FILE.$$" "$REPOS_CACHE_FILE" )
    clones=$(repo_clones)
    repos_rows "$login" "$account" "$kind" "$show_all" "$clones" <<< "$all"
}

# Las filas de repos (C| y R|) de las paginas de GitHub (por la entrada):
# repos_rows <usuario> <cuenta> <tipo> <todos (1/0)> <clones (repo_clones)>
function repos_rows() {
    python3 -I -c '
import json, os, re, sys
login, account, kind, prefixes, show_all, base, clones = sys.argv[1:8]
sys.stdout.reconfigure(errors="replace")
prefixes = prefixes.split()
have = dict(l.split(" ", 1) for l in clones.splitlines() if " " in l)
dec = json.JSONDecoder()
text, i, repos = sys.stdin.read(), 0, []
while True:
    while i < len(text) and text[i].isspace():
        i += 1
    if i >= len(text):
        break
    page, i = dec.raw_decode(text, i)
    repos += page
clean = lambda v: re.sub(r"\s+", " ", re.sub(r"[|\r\n\t]", " ", v or "")).strip()
rows = []
for r in repos:
    if r.get("archived") or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._][A-Za-z0-9._-]*", r.get("full_name", "")):
        continue
    if kind != "Organization" and r["owner"]["login"].lower() != account.lower():
        continue
    pre = next((p for p in prefixes if r["name"].startswith(p)), "")
    rows.append((r, pre))
shown = [x for x in rows if show_all == "1" or not prefixes or x[1]]
print("C|%s|%s|%s|%d|%d" % (login, account, kind, len(rows), len(shown)))
for r, pre in shown:
    name, full = r["name"], r["full_name"]
    folder = have.get(full.lower(), "")
    state = "clonado" if folder else ("ocupado" if os.path.lexists(os.path.join(base, name)) else "nuevo")
    print("R|%s|%s|%d|%s|%s|%s|%s|%s|%s|%s" % (full, name, 1 if r.get("private") else 0, (r.get("pushed_at") or "")[:10],
          clean(r.get("default_branch")), pre, clean(r.get("homepage")), clean(r.get("description"))[:300], state, folder or (name if state == "ocupado" else "")))
' "$1" "$2" "$3" "$(github_conf PREFIJOS)" "$4" "$HTDOCS_DIR" "$5"
}

# git pull seguro de un clon: repo_pull <carpeta> <direccion SSH o nada> <fichero de servidores conocidos>.
# Si no se puede (sin conexion, o choca con lo que no se ha subido o guardado), no se toca nada
function repo_pull() {
    local dir=$1 ssh_url=$2 known=$3 branch origin from=() up
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD) || { echo "$dir no está en una rama (HEAD suelto): no se toca"; return 1; }
    origin=$(git -C "$dir" config --get remote.origin.url)
    # (un origin por https de un privado no se puede leer sin preguntar: se trae por SSH, su rama)
    if [[ "$origin" == https://* ]] && [ -n "$ssh_url" ]; then
        up=$(git -C "$dir" config --get "branch.$branch.merge")
        from=("$ssh_url" "${up#refs/heads/}")
        [ -n "${from[1]}" ] || from[1]=$branch
    fi
    # (sin terminal, sin preguntar nada y solo con servidores conocidos, como repo_clone)
    if ! GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false GIT_LFS_SKIP_SMUDGE=1 \
            GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o 'UserKnownHostsFile=~/.ssh/known_hosts $known'" \
            no_tty git -C "$dir" -c core.hooksPath=/dev/null -c credential.helper= -c protocol.allow=never \
            -c protocol.ssh.allow=always -c protocol.https.allow=always pull --no-rebase --no-edit "${from[@]}"; then
        [ -f "$dir/.git/MERGE_HEAD" ] && git -C "$dir" merge --abort 2> /dev/null
        echo "No se han podido traer los cambios: choca con lo que tienes sin subir o sin guardar en $dir, o no hay conexión."
        echo "No se ha tocado nada. Guarda o sube tus cambios (git status) y vuelve a probar."
        return 1
    fi
}

# repo-traer <dueño/repo> [--actualizar]: lo clona por SSH (con tu clave) en htdocs, en una carpeta con
# su nombre. Si ya esta clonado en un proyecto, lo dice (EXISTE|carpeta, y sale con 3) y, con
# --actualizar, trae sus cambios con git pull (si chocan con los tuyos, no se toca nada y se dice)
function repo_fetch() {
    local full=$1 name dir folder known ssh_url branch
    [[ "$full" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._][A-Za-z0-9._-]*$ ]] && [[ "$full" != *..* ]] || { echo "Repositorio no válido: $full (dueño/repositorio)"; return 1; }
    command -v git > /dev/null || { echo "Hace falta git para clonar el repositorio"; return 1; }
    name=${full#*/} ssh_url="git@github.com:$full.git"
    folder=$(repo_clones | awk -v r="${full,,}" '$1 == r { print $2; exit }')
    known=$(mktemp /tmp/lvm-conocidos.XXXXXX) || return 1
    printf '%s\n' "$GIT_KNOWN_HOSTS" > "$known"
    if [ -n "$folder" ]; then
        dir=$HTDOCS_DIR/$folder
        if [ "$2" != --actualizar ]; then
            rm -f "$known"
            echo "EXISTE|$folder"
            echo "$full ya está clonado en $dir"
            return 3
        fi
        echo "$full: se traen sus cambios a $dir (git pull)"
        [ "$DRY" -eq 1 ] && { rm -f "$known"; echo "  [simulacion] git pull en $dir"; return 0; }
        if ! repo_pull "$dir" "$ssh_url" "$known"; then
            rm -f "$known"
            return 1
        fi
        branch=$(git -C "$dir" symbolic-ref --short -q HEAD)
        rm -f "$known"
        echo "$folder, al día con GitHub (rama $branch)"
        return 0
    fi
    dir=$HTDOCS_DIR/$name
    if [ -e "$dir" ] || [ -L "$dir" ]; then
        rm -f "$known"
        echo "Ya hay una carpeta $name en $HTDOCS_DIR que no es un clon de $full: muévela o renómbrala antes"
        return 1
    fi
    [ -w "$HTDOCS_DIR" ] || { rm -f "$known"; echo "No puedes escribir en $HTDOCS_DIR: el proyecto se clona con tu usuario, sin sudo"; return 1; }
    echo "Clonando $full por SSH en $dir..."
    [ "$DRY" -eq 1 ] && { rm -f "$known"; echo "  [simulacion] git clone $ssh_url $dir"; return 0; }
    if ! repo_clone "$ssh_url" "$dir" "$known"; then
        rm -f "$known"
        echo "No se ha podido clonar: hace falta tu clave SSH configurada en GitHub (ssh -T git@github.com lo comprueba)"
        return 1
    fi
    rm -f "$known"
    htdocs_close_world "$dir"
    # (como los de Montar nuevo proyecto: el dominio de su base no se falsea solo)
    mkdir -p "$HOME/.lvm-instalador" && { grep -qxF -- "$name" "$REPO_PROJECTS_FILE" 2> /dev/null \
        || printf '%s\n' "$name" >> "$REPO_PROJECTS_FILE"; }
    echo "Listo: $name está en Proyectos (cárgalo con su versión de PHP y su BBDD)"
}

# gui-proyecto-git <carpeta>: lo que hay que saber antes de copiar encima el codigo de produccion:
# G|es un repositorio (1/0)|rama|cambios sin commit|commits sin subir|tiene origin (1/0)
function gui_project_git() {
    local dir=$HTDOCS_DIR/${1%/} branch dirty ahead origin=0
    valid_project "${1%/}" > /dev/null || return 1
    if [ -L "$dir" ] || [ ! -e "$dir/.git" ] || ! command -v git > /dev/null; then
        echo "G|0||0|0|0"
        return 0
    fi
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD)
    # (sin los ayudantes que pudiera traer su configuracion: aqui solo se lee)
    dirty=$(git -C "$dir" -c core.fsmonitor=false -c core.hooksPath=/dev/null status --porcelain 2> /dev/null | wc -l | tr -d ' ')
    ahead=$(git -C "$dir" rev-list --count '@{u}..HEAD' 2> /dev/null)
    [ -n "$(git -C "$dir" config --get remote.origin.url)" ] && origin=1
    echo "G|1|${branch//|/_}|${dirty:-0}|${ahead:-0}|$origin"
}

# Copia el codigo de produccion (.zip, .tar.gz o carpeta) en un proyecto:
#   python3 -c "$PROJECT_CODE_PY" <carpeta del proyecto> <origen> <fusionar|sobrescribir> <copias> <temporal> <simular 1/0>
# Fusionar copia lo que trae y deja lo demas; sobrescribir ademas quita lo que no trae. .git no se toca
# nunca. Lo sustituido o quitado se mueve antes a <copias>, y lo que no cambia no se escribe. De un
# paquete no se saca nada fuera de la carpeta (rutas con .. o absolutas) ni enlaces ni dispositivos: el
# codigo de produccion es de fuera. Si todo va dentro de una carpeta (public_html), se usa lo de dentro.
PROJECT_CODE_PY='
import filecmp, os, shutil, signal, stat, sys, tarfile, tempfile, zipfile

target, source, mode, backup, tmp_base, simulate = sys.argv[1:7]
simulate = simulate == "1"
SKIP = {".git", "__MACOSX", ".DS_Store"}
sys.stdout.reconfigure(errors="replace", line_buffering=True)
counts = {"copied": 0, "same": 0, "removed": 0, "skipped": 0}
errors, seen = [], set()


def stop(_sig, _frame):
    raise SystemExit(130)


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGHUP, stop)


def fail(text):
    print(text)
    raise SystemExit(1)


def safe_path(root, name):
    """La ruta de un miembro del paquete dentro de root, o None si se saldria o no es valida."""
    name = name.replace(chr(92), "/")
    parts = [p for p in name.split("/") if p not in ("", ".")]
    if name.startswith("/") or not parts or ".." in parts or any(chr(0) in p or ":" in p[:2] for p in parts):
        return None
    return os.path.join(root, *parts)


def write_member(path, data, executable):
    os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
    with open(path, "wb") as out:
        shutil.copyfileobj(data, out, 1024 * 1024)
    os.chmod(path, 0o755 if executable else 0o644)


def extract_zip(path, root):
    with zipfile.ZipFile(path) as z:
        members = z.infolist()
        need = sum(m.file_size for m in members)
        free = shutil.disk_usage(root).free
        if need > free:
            fail("No cabe: hacen falta %d MB para abrirlo y hay %d MB libres" % (need >> 20, free >> 20))
        for m in members:
            if m.flag_bits & 1:
                fail("El .zip lleva contraseña: quitasela o descomprimelo y elige la carpeta")
            kind = stat.S_IFMT(m.external_attr >> 16)
            out = safe_path(root, m.filename)
            if out is None or kind not in (0, stat.S_IFREG, stat.S_IFDIR):
                counts["skipped"] += 1
            elif m.is_dir():
                os.makedirs(out, mode=0o755, exist_ok=True)
            else:
                with z.open(m) as data:
                    write_member(out, data, (m.external_attr >> 16) & 0o111)


def extract_tar(path, root):
    with tarfile.open(path, "r:*") as t:
        for m in t:
            out = safe_path(root, m.name)
            if out is None or not (m.isreg() or m.isdir()):
                counts["skipped"] += 1
            elif m.isdir():
                os.makedirs(out, mode=0o755, exist_ok=True)
            else:
                write_member(out, t.extractfile(m), m.mode & 0o111)


def entries(path):
    return [e for e in os.scandir(path) if e.name not in SKIP]


def inner_root(root):
    """Si todo va dentro de una sola carpeta (public_html), lo de dentro. wp-content solo no: si en el
    proyecto hay una con ese nombre, va en su sitio."""
    while True:
        found = entries(root)
        if len(found) != 1 or not found[0].is_dir(follow_symlinks=False) \
                or os.path.lexists(os.path.join(target, found[0].name)):
            return root
        print("Se usa lo que hay dentro de %s/" % found[0].name)
        root = found[0].path


def save_old(path, rel):
    """Mueve lo que hay en path a las copias (si no se puede copiar, el error lo recoge quien llama)."""
    if simulate:
        return
    dest = os.path.join(backup, rel)
    os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
    try:
        os.rename(path, dest)
    except OSError:
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.copytree(path, dest, symlinks=True)
            shutil.rmtree(path)
        else:
            shutil.copy2(path, dest, follow_symlinks=False)
            os.unlink(path)


def tick():
    done = counts["copied"] + counts["same"] + counts["removed"]
    if done and done % 5000 == 0:
        print("  %d ficheros revisados..." % done)


def is_real_dir(path):
    return os.path.isdir(path) and not os.path.islink(path)


def sync(src, dst, rel):
    for e in sorted(entries(src), key=lambda x: x.name):
        sub = os.path.join(rel, e.name)
        out = os.path.join(dst, e.name)
        seen.add(sub)
        try:
            if e.is_symlink():
                counts["skipped"] += 1
                seen.discard(sub)
            elif e.is_dir(follow_symlinks=False):
                # (un enlace en el proyecto no se sigue: escribiria fuera de la carpeta)
                if os.path.lexists(out) and not is_real_dir(out):
                    save_old(out, sub)
                if not simulate and not os.path.lexists(out):
                    os.mkdir(out, 0o755)
                sync(e.path, out, sub)
            elif e.is_file(follow_symlinks=False):
                copy_file(e, out, sub)
            else:
                counts["skipped"] += 1
                seen.discard(sub)
            tick()
        except OSError as exc:
            errors.append("%s: %s" % (sub, exc.strerror or exc))


def copy_file(e, out, sub):
    exists = os.path.lexists(out)
    if exists and not os.path.islink(out) and os.path.isfile(out) \
            and os.path.getsize(out) == e.stat().st_size and filecmp.cmp(e.path, out, shallow=False):
        counts["same"] += 1
        return
    counts["copied"] += 1
    if simulate:
        return
    # (primero la copia nueva y luego se aparta la de antes: si no cabe, el proyecto sigue como estaba)
    fd, part = tempfile.mkstemp(prefix=".lvm-parte-", dir=os.path.dirname(out))
    try:
        with os.fdopen(fd, "wb") as dest, open(e.path, "rb") as data:
            shutil.copyfileobj(data, dest, 1024 * 1024)
        os.chmod(part, (e.stat().st_mode & 0o755) | 0o644)
        if exists:
            save_old(out, sub)
        os.replace(part, out)
    except BaseException:
        if os.path.exists(part):
            os.unlink(part)
        raise


def remove_rest(dst, rel):
    for e in sorted(os.scandir(dst), key=lambda x: x.name):
        sub = os.path.join(rel, e.name)
        if e.name == ".git":
            continue
        try:
            if sub not in seen:
                has_git = is_real_dir(e.path) and any(".git" in dirs for _r, dirs, _f in os.walk(e.path))
                if has_git:
                    remove_rest(e.path, sub)
                else:
                    counts["removed"] += 1
                    save_old(e.path, sub)
            elif is_real_dir(e.path):
                remove_rest(e.path, sub)
            tick()
        except OSError as exc:
            errors.append("%s: %s" % (sub, exc.strerror or exc))


def main():
    real_target = os.path.realpath(target)
    work = None
    if os.path.isdir(source):
        root = os.path.realpath(source)
        if root == real_target or (root + os.sep).startswith(real_target + os.sep) \
                or (real_target + os.sep).startswith(root + os.sep):
            fail("La carpeta elegida y la del proyecto se solapan: elige otra")
    else:
        os.makedirs(tmp_base, mode=0o700, exist_ok=True)
        work = tempfile.mkdtemp(prefix="actualizar-", dir=tmp_base)
        root = work
    try:
        if work:
            print("Abriendo %s..." % os.path.basename(source))
            try:
                if zipfile.is_zipfile(source):
                    extract_zip(source, work)
                elif tarfile.is_tarfile(source):
                    extract_tar(source, work)
                else:
                    fail("%s no es un .zip, un .tar.gz ni una carpeta" % os.path.basename(source))
            except (OSError, zipfile.BadZipFile, tarfile.TarError, EOFError) as exc:
                fail("No se ha podido abrir %s: %s" % (os.path.basename(source), exc))
        root = inner_root(root)
        if not any(True for _ in entries(root)):
            fail("No trae ningun fichero: no se ha tocado nada")
        sync(root, target, "")
        if mode == "sobrescribir":
            remove_rest(target, "")
    finally:
        if work:
            shutil.rmtree(work, ignore_errors=True)
    print("%s%d copiados, %d iguales (no se tocan), %d quitados"
          % ("[simulacion] " if simulate else "", counts["copied"], counts["same"], counts["removed"]))
    if counts["skipped"]:
        print("%d no se han copiado (enlaces, dispositivos o rutas fuera de la carpeta)" % counts["skipped"])
    if os.path.isdir(backup):
        print("Lo que se ha sustituido o quitado esta en %s" % backup)
    if errors:
        print("No se han podido copiar o quitar %d:" % len(errors))
        for line in errors[:15]:
            print("  " + line)
        raise SystemExit(1)


main()
'

# La BBDD que usa ahora un proyecto, de su configuracion: hay que leerla antes de copiar encima la de produccion
function project_config_db() {
    local db=""
    if is_prestashop "$1"; then
        db=$(ps_config "$1" | cut -d'|' -f1)
    elif is_wordpress "$1"; then
        db=$(wp_config_read "$HTDOCS_DIR/$1/wp-config.php" | head -1)
    fi
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] && echo "$db"
}

# ¿Ha quedado su configuracion con la BBDD y la direccion locales? (al volver a cargarlo, un aviso no
# para la carga: sin esto, se diria que esta actualizado con el wp-config.php de produccion)
function project_config_local() {
    local folder=$1 db=$2 file=$HTDOCS_DIR/$1/wp-config.php now
    [ -n "$db" ] || { echo "Aviso: no se sabe qué BBDD usa $folder: revisa su configuración"; return 1; }
    if is_prestashop "$folder"; then
        now=$(ps_config "$folder" | cut -d'|' -f1)
        [ "$now" == "$db" ] && return 0
        echo "Aviso: la configuración de $folder usa la BBDD ${now:-(ninguna)} y tendría que usar $db"
        return 1
    fi
    is_wordpress "$folder" || return 0
    now=$(wp_config_read "$file" | head -1)
    if [ "$now" != "$db" ]; then
        echo "Aviso: el wp-config.php de $folder usa la BBDD ${now:-(ninguna)} y tendría que usar $db"
        return 1
    fi
    wp_config_has_url "$file" "$(wp_local_url "$folder")" && return 0
    echo "Aviso: el wp-config.php de $folder no lleva WP_SITEURL y WP_HOME con su dirección local"
    return 1
}

# actualizar-proyecto <carpeta> [--codigo <zip, tar.gz o carpeta>] [--modo fusionar|sobrescribir] [--pull]
#                     [--bd <fichero>] [--base <base>]
# El proyecto con lo de produccion, en este orden: git pull (si se pide), el codigo, la BBDD (con la carga
# protegida de importar-bd) y volver a cargarlo (su configuracion vuelve a la base y al dominio locales),
# comprobando que ha quedado asi. Si un paso falla, los siguientes no se hacen. --base sin --bd: la BBDD
# que usa (si no, la asociada a la carpeta o la de su configuracion antes de copiar)
function project_update() {
    local folder=${1%/} source="" mode=fusionar pull=0 file="" db="" dir stamp copies full ssh_url="" known load_db
    shift
    while [ $# -gt 0 ]; do
        case $1 in
            --codigo) source=$2; shift ;;
            --modo) mode=$2; shift ;;
            --pull) pull=1 ;;
            --bd) file=$2; shift ;;
            --base) db=$2; shift ;;
            *) folder="" ;;
        esac
        shift
    done
    if [ -z "$folder" ] || { [ -z "$source" ] && [ -z "$file" ]; } || [[ "$mode" != fusionar && "$mode" != sobrescribir ]]; then
        echo "Uso: lvm-instalador actualizar-proyecto <carpeta> [--codigo <zip, tar.gz o carpeta>] [--modo fusionar|sobrescribir] [--pull] [--bd <fichero>] [--base <base>]"
        return 1
    fi
    valid_project "$folder" || return 1
    dir=$HTDOCS_DIR/$folder
    if [ -L "$dir" ] || [ ! -d "$dir" ]; then
        echo "No existe la carpeta $dir"
        return 1
    fi
    [ -z "$source" ] || [ -r "$source" ] || { echo "No se puede leer $source"; return 1; }
    if [ -n "$file" ]; then
        [ -f "$file" ] && [ -r "$file" ] || { echo "No se puede leer el fichero $file"; return 1; }
        db_connect || return $?
    fi
    { [ -z "$file" ] && [ -z "$db" ]; } || db_valid_name "$db" || return 1
    # Con la BBDD de ahora: el codigo de produccion trae la configuracion de produccion
    load_db=${db:-$(saved_project_db "$folder")}
    [ -n "$load_db" ] || load_db=$(project_config_db "$folder")
    # La contraseña antes de cambiar nada: cancelarla deja el proyecto como estaba
    if [ "$DRY" -eq 0 ] && [ -n "$SUDO" ] && ! sudo -v; then
        echo "Cancelado: no se ha cambiado nada"
        return 1
    fi

    local steps=()
    [ -n "$source" ] && [ "$pull" -eq 1 ] && steps+=("Traer los cambios con git pull")
    [ -n "$source" ] && steps+=("Copiar el código de producción")
    [ -n "$file" ] && steps+=("Cargar la BBDD $db")
    steps+=("Volver a cargar el proyecto" "Comprobar su configuración")
    task_plan "Actualizando $folder" "${steps[@]}"
    if [ -n "$source" ] && [ "$pull" -eq 1 ]; then
        task_step
        echo "== git pull en $dir"
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] git pull en $dir"
        else
            full=$(repo_clones | awk -v f="$folder" '$2 == f { print $1; exit }')
            [ -n "$full" ] && ssh_url="git@github.com:$full.git"
            known=$(mktemp /tmp/lvm-conocidos.XXXXXX) || return 1
            printf '%s\n' "$GIT_KNOWN_HOSTS" > "$known"
            if ! repo_pull "$dir" "$ssh_url" "$known"; then
                rm -f "$known"
                echo "No se ha copiado el codigo de produccion ni se ha cargado la BBDD."
                return 1
            fi
            rm -f "$known"
        fi
    fi
    if [ -n "$source" ]; then
        task_step
        echo "== Codigo de produccion ($([ "$mode" == sobrescribir ] && echo "sobrescribiendo" || echo "fusionando") en $dir)"
        stamp=$(date +%Y%m%d-%H%M%S)
        copies=$HOME/lvm-copias/$folder-antes-de-actualizar-$stamp
        [ "$DRY" -eq 1 ] || mkdir -p -m 700 "$HOME/lvm-copias"
        if ! python3 -I -c "$PROJECT_CODE_PY" "$dir" "$source" "$mode" "$copies" "$HOME/.lvm-instalador/temporal" "$DRY"; then
            echo "No se ha cargado la BBDD: revisa lo anterior."
            return 1
        fi
        htdocs_close_world "$dir"
    fi
    if [ -n "$file" ]; then
        task_step
        echo "== BBDD de produccion"
        import_database "$file" "$db" --crear --proyecto "$folder" || return 1
    fi
    task_step
    echo "== Volviendo a cargar $folder (su configuracion, a la base y al dominio locales)"
    load_project "$folder" "" "$load_db" || return 1
    task_step
    if [ "$DRY" -eq 0 ] && ! project_config_local "$folder" "$load_db"; then
        echo "El código y la BBDD están actualizados, pero la web puede no abrir en local: revisa lo anterior."
        return 1
    fi
    echo "Proyecto actualizado: $folder"
}

# ¿Direccion de un repositorio que se puede clonar? Solo https:// o ssh (git@servidor:ruta o
# ssh://git@servidor/ruta), con servidor y ruta sin caracteres raros ni un - al principio (git los
# tomaria como opciones). Nada de file://, ext:: ni rutas locales
function git_url_ok() {
    local host='[A-Za-z0-9][A-Za-z0-9.-]*' path='[A-Za-z0-9_~][A-Za-z0-9._~/-]*'
    [[ "$1" =~ ^https://$host(:[0-9]{1,5})?/$path$ ]] || [[ "$1" =~ ^git@$host:$path$ ]] \
        || [[ "$1" =~ ^ssh://git@$host(:[0-9]{1,5})?/$path$ ]]
}

# montar-proyecto <url de git> <carpeta> <version> <base> [volcado]: proyecto nuevo desde un
# repositorio (GitHub u otro). Lo clona en htdocs, lo carga en esa version de PHP, crea su BBDD y,
# si se indica, carga en ella el volcado (con la carga protegida de importar-bd). El clon va con tu
# usuario (sin sudo), sin submodulos ni ganchos y solo por https o ssh; sin preguntas: un
# repositorio privado por https falla (se usa la direccion SSH con tu clave)
# Clona un repositorio con tu usuario: repo_clone <direccion> <carpeta> <known_hosts de mas>. Sin
# terminal (git y ssh leen tu configuracion: no pueden usar el permiso de sudo recordado ni quedarse
# leyendola) y sin git-lfs (su .lfsconfig llevaria las descargas a otro servidor)
function repo_clone() {
    local url=$1 dest=$2 known=$3
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false GIT_LFS_SKIP_SMUDGE=1 \
        GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o 'UserKnownHostsFile=~/.ssh/known_hosts $known'" \
        no_tty git -c protocol.allow=never -c protocol.https.allow=always -c protocol.ssh.allow=always \
            -c core.hooksPath=/dev/null -c credential.helper= \
            -c filter.lfs.process= -c filter.lfs.smudge= -c filter.lfs.required=false \
            clone --no-recurse-submodules -- "$url" "$dest"
}

# La direccion SSH de una https de GitHub, GitLab o Bitbucket (https://github.com/usuario/repo(.git) ->
# git@github.com:usuario/repo.git; en GitLab, tambien con subgrupos). Nada si es de otro servidor
function repo_ssh_url() {
    [[ "$1" =~ ^https://(github\.com|gitlab\.com|bitbucket\.org)/([A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+)/?$ ]] || return 1
    local host=${BASH_REMATCH[1]} path=${BASH_REMATCH[2]}
    path=${path%.git}
    [[ "$path" == */* ]] && [[ "$path" != *..* ]] || return 1
    echo "git@$host:$path.git"
}

function mount_project() {
    local url=$1 folder=$2 version=$3 db=$4 file=$5 dest dir owner
    if [ -z "$url" ] || [ -z "$folder" ] || [ -z "$version" ] || [ -z "$db" ]; then
        echo "Uso: lvm-instalador montar-proyecto <url de git> <carpeta> <version> <base de datos> [volcado]"

        return 1
    fi
    if ! git_url_ok "$url"; then
        echo "La direccion del repositorio no es valida: usa https://servidor/usuario/repositorio(.git)"
        echo "o git@servidor:usuario/repositorio.git"

        return 1
    fi
    if ! [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$ ]] || [ "$folder" == "$EMPTY_PROJECT" ]; then
        echo "El nombre de la carpeta solo puede llevar letras sin acentos, numeros, punto, _ y -"

        return 1
    fi
    dest=$HTDOCS_DIR/$folder
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        echo "Ya existe $dest: elige otro nombre para la carpeta"

        return 1
    fi
    dir="${TEST_DIR:-/opt}/lampp-$version"
    if ! valid_version_name "$version" || [ ! -d "$dir" ] || [ -L "$dir" ]; then
        echo "No existe la version $version"

        return 1
    fi
    db_valid_name "$db" || return 1
    owner=$(data_owner "$dir"); owner="${TEST_DIR:-/opt}/lampp-${owner:-$version}"
    if db_names "$owner" | grep -qxF "$db"; then
        echo "Ya hay una BBDD $db en esa version: elige otro nombre"

        return 1
    fi
    if [ -n "$file" ] && { [ ! -f "$file" ] || [ -L "$file" ]; }; then
        echo "No existe el fichero $file"

        return 1
    fi
    if ! command -v git > /dev/null; then
        echo "Hace falta git para clonar el repositorio: sudo apt install git"

        return 1
    fi
    if [ ! -w "$HTDOCS_DIR" ]; then
        echo "No puedes escribir en $HTDOCS_DIR: el proyecto se clona con tu usuario, sin sudo"

        return 1
    fi

    task_plan "Montando el proyecto $folder" "Clonar el repositorio" "Cargarlo en lampp-$version" "Preparar la BBDD $db"
    task_step
    echo "1/3 Clonando $url en $dest..."
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] git clone --no-recurse-submodules -- $url $dest"
        echo "2/3 [simulacion] cargar-proyecto $folder $version $db"
        echo "3/3 [simulacion] BBDD $db: $([ -n "$file" ] && echo "importar-bd $file $db --crear" || echo "crear-bd $db")"

        return 0
    fi
    # Por ssh, solo servidores cuya clave ya conoces (~/.ssh/known_hosts) o las publicadas de GitHub,
    # GitLab y Bitbucket: un servidor nuevo no se acepta sin mirar (en una red ajena o con /etc/hosts
    # cambiado te darian otro repositorio, y su PHP corre con tu usuario)
    local known
    # (en /tmp y no en $TMPDIR, que viene de la sesion: va entre comillas en GIT_SSH_COMMAND)
    known=$(mktemp /tmp/lvm-conocidos.XXXXXX) || return 1
    printf '%s\n' "$GIT_KNOWN_HOSTS" > "$known"
    # Un repositorio privado de GitHub, GitLab o Bitbucket por https no se puede clonar sin preguntar
    # usuario y contraseña (y aqui no se preguntan): se prueba solo la misma direccion por SSH, con tu
    # clave. Solo con esos tres, cuyas claves de servidor van en GIT_KNOWN_HOSTS
    local ssh_url ok=0
    if repo_clone "$url" "$dest" "$known"; then
        ok=1
    elif ssh_url=$(repo_ssh_url "$url") && [ ! -e "$dest" ]; then
        echo "Por https no se puede (¿repositorio privado?): se prueba por SSH, $ssh_url"
        repo_clone "$ssh_url" "$dest" "$known" && ok=1
    fi
    if [ $ok -eq 0 ]; then
        rm -f "$known"
        echo "No se ha podido clonar el repositorio. Si es privado, hace falta tu clave SSH ya configurada"
        echo "en GitHub, GitLab o Bitbucket (su direccion SSH es git@github.com:usuario/repositorio.git)."
        echo "Si es por SSH a un servidor que no es GitHub, GitLab ni Bitbucket y dice «Host key"
        echo "verification failed», conectate una vez a mano para comprobar y aceptar su clave"
        echo "(ssh -T git@servidor) y vuelve a intentarlo."

        return 1
    fi
    rm -f "$known"
    htdocs_close_world "$dest"
    # Apuntada como montada desde un repositorio: el dominio de su base no se falsea solo (ver
    # load_project_domain)
    mkdir -p "$HOME/.lvm-instalador" && { grep -qxF -- "$folder" "$REPO_PROJECTS_FILE" 2> /dev/null \
        || printf '%s\n' "$folder" >> "$REPO_PROJECTS_FILE"; }

    task_step
    echo "2/3 Cargando $folder en lampp-$version..."
    load_project "$folder" "$version" "$db" || { echo "El proyecto esta clonado en $dest, pero no se ha podido cargar."; return 1; }

    task_step
    echo "3/3 BBDD $db..."
    if [ -n "$file" ]; then
        import_database "$file" "$db" --crear || return 1
    else
        create_database "$db" || return 1
    fi
    # Al cargarla, la base aun no existia: ahora que esta, su configuracion. Tienda PrestaShop: su dominio
    # (shop_url de la base), su vhost, su certificado y el dominio falseado. WordPress: wp-config.php con
    # la base (el repositorio no suele traerlo, o trae el de produccion)
    if [ -n "$file" ] && { is_prestashop "$folder" || is_wordpress "$folder"; }; then
        load_project_domain "$folder" "$db" || return 1
    fi
    echo "Proyecto nuevo montado: $folder en lampp-$version con la BBDD $db"
}

# Carga un proyecto: activa la version (si se indica y no es la activa) y apunta el enlace del vhost
# a la carpeta del proyecto (lo mismo que unlink web.local; ln -s <carpeta>/ web.local)
# Cargar un proyecto es todo o nada: la contraseña se pide antes de cambiar nada y, si se cancela (la
# ventana manda TERM a la tarea) o falla un paso, el enlace del vhost vuelve al proyecto de antes, la
# version activa a la de antes y Apache se recarga. Lo de antes, en LOAD_UNDO_*
LOAD_UNDO_LINK="" LOAD_UNDO_TARGET="" LOAD_UNDO_ACTIVE=""

function load_project_undo() {
    trap - TERM INT HUP
    [ -n "$LOAD_UNDO_LINK" ] || return 0
    local sudo="" now
    echo "Se deja como estaba: $LOAD_UNDO_LINK -> ${LOAD_UNDO_TARGET:-nada}"
    [ -w "$HTDOCS_DIR" ] || sudo=sudo
    now=$(readlink "$HTDOCS_DIR/$LOAD_UNDO_LINK" 2> /dev/null)
    if [ "$now" != "$LOAD_UNDO_TARGET" ]; then
        if [ -n "$LOAD_UNDO_TARGET" ]; then
            run $sudo ln -sfn "$LOAD_UNDO_TARGET" "$HTDOCS_DIR/$LOAD_UNDO_LINK"
        elif [ -L "$HTDOCS_DIR/$LOAD_UNDO_LINK" ]; then
            run $sudo unlink "$HTDOCS_DIR/$LOAD_UNDO_LINK"
        fi
    fi
    if [ -n "$LOAD_UNDO_ACTIVE" ] && [ "$(readlink /opt/lampp)" != "$LOAD_UNDO_ACTIVE" ]; then
        use_lampp "${LOAD_UNDO_ACTIVE#/opt/lampp-}"
    elif [ -f /opt/lampp/logs/httpd.pid ]; then
        run sudo /opt/lampp/lampp reloadapache > /dev/null
    fi
    LOAD_UNDO_LINK=""
}

function load_project() {
    local folder=${1%/} version=$2 link rc

    valid_project "$folder" || return 1
    if [ -n "$version" ] && { ! valid_version_name "$version" || [ ! -d "/opt/lampp-$version" ]; }; then
        echo "No existe la version $version de lampp en el sistema"

        return 1
    fi
    # La contraseña antes de cambiar nada: cancelarla deja el proyecto de antes cargado
    if [ "$DRY" -eq 0 ] && [ -n "$SUDO" ] && ! sudo -v; then
        echo "Cancelado: no se ha cambiado nada"
        return 1
    fi

    link=$(project_link)
    if [ -z "$link" ]; then
        create_project_vhost || return 1
        link=$PROJECT_VHOST
    fi

    if [ "$folder" == "$link" ]; then
        echo "$folder es el propio enlace del vhost, no un proyecto"

        return 1
    fi
    LOAD_UNDO_LINK=$link LOAD_UNDO_TARGET=$(readlink "$HTDOCS_DIR/$link" 2> /dev/null)
    LOAD_UNDO_ACTIVE=$(readlink /opt/lampp 2> /dev/null)
    [ "$DRY" -eq 0 ] && trap 'load_project_undo; exit 130' TERM INT HUP
    load_project_steps "$folder" "$version" "$link" "$3"
    rc=$?
    if [ $rc -ne 0 ] && [ "$DRY" -eq 0 ]; then
        load_project_undo
    fi
    trap - TERM INT HUP
    LOAD_UNDO_LINK=""
    return $rc
}

# PrestaShop 1.7+ guarda su configuracion (con la BBDD) en var/cache: si es la de otro sitio (la del
# contenedor de Docker, db, o la de produccion), la tienda no conecta con su BBDD en LAMPP (error 500).
# Se aparta (a ~/lvm-copias) la cache cuya BBDD no es la de app/config/parameters.php: se rehace sola
function ps_stale_cache() {
    local root=$HTDOCS_DIR/$1 env
    [ -f "$root/app/config/parameters.php" ] || return 0
    for env in $(python3 -I - "$root" <<'EOF'
import glob, os, re, sys
root = sys.argv[1]
def db(path):
    try:
        text = open(path, encoding="utf-8", errors="replace").read(200000)
    except OSError:
        return None
    return tuple((re.search(r"""['"]%s['"]\s*=>\s*['"]([^'"]*)['"]""" % k, text) or [None, ""])[1]
                 for k in ("database_host", "database_name", "database_user"))
want = db(os.path.join(root, "app/config/parameters.php"))
for cached in glob.glob(os.path.join(root, "var/cache/*/appParameters.php")):
    env = os.path.basename(os.path.dirname(cached))
    if want and re.fullmatch(r"[A-Za-z0-9_-]+", env) and db(cached) not in (None, want):
        print(env)
EOF
    ); do
        [ -L "$root/var/cache/$env" ] && continue
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] se aparta var/cache/$env de $1 (lleva otra BBDD)"
            continue
        fi
        mkdir -p -m 700 "$HOME/lvm-copias"
        mv "$root/var/cache/$env" "$HOME/lvm-copias/$1-cache-$env-$(date +%Y%m%d-%H%M%S)" \
            && echo "La cache de la tienda (var/cache/$env) era de otra BBDD (de Docker o de produccion): apartada en ~/lvm-copias, se rehace sola"
    done
    return 0
}

# Los cambios de load_project (ver arriba): <carpeta> <version> <enlace> <base>
function load_project_steps() {
    local folder=$1 version=$2 link=$3 sudo="" secured=1
    htdocs_close_world "$HTDOCS_DIR/$folder"
    ps_stale_cache "$folder"

    [ -w "$HTDOCS_DIR" ] || sudo=sudo
    if [ -L "$HTDOCS_DIR/$link" ]; then
        run $sudo unlink "$HTDOCS_DIR/$link" || return 1
    fi
    run $sudo ln -s "$folder/" "$HTDOCS_DIR/$link" || return 1

    # Apache con tu usuario (User/Group), si la version no lo tiene: se aplica al arrancar o recargar
    local web_dir=$(active_dir)
    [ -n "$version" ] && web_dir=/opt/lampp-$version
    [ -n "$web_dir" ] && ensure_web_user "$web_dir"
    # Solo para este equipo: si cambia algo con la version en marcha, se reinicia para aplicarlo
    if [ -n "$web_dir" ]; then
        secure_lampp "$web_dir"
        case $? in
            0) secured=0 ;;
            2) secure_failed 2 "$web_dir" && return 1 ;;
        esac
        vhosts_root && secured=0
    fi

    if [ -n "$version" ] && [ "$(readlink /opt/lampp)" != "/opt/lampp-$version" ]; then
        echo "Activando lampp-$version..."
        use_lampp "$version" || return 1
    elif [ -L /opt/lampp ] && ! lampp_running; then
        echo "Arrancando $(readlink /opt/lampp | sed 's:^/opt/::')..."
        run sudo /opt/lampp/lampp start
    elif [ $secured -eq 0 ]; then
        echo "Reiniciando $(readlink /opt/lampp | sed 's:^/opt/::') para que solo se pueda entrar desde este equipo..."
        run sudo /opt/lampp/lampp restart > /dev/null || { echo "No se ha podido reiniciar. Reinicia la version activa."; return 1; }
    elif [ -f /opt/lampp/logs/httpd.pid ]; then
        # Cada proceso de PHP recuerda a donde apuntaba el enlace (realpath_cache, 120 s) y seguiria
        # sirviendo el proyecto anterior: recarga suave de Apache (y PHP-FPM en las pilas propias)
        echo "Recargando Apache para que PHP no siga sirviendo el proyecto anterior..."
        run sudo /opt/lampp/lampp reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi

    # Tienda PrestaShop: su dominio con vhost, certificado y falseado en /etc/hosts. Otro proyecto:
    # ningun dominio falseado
    # La base con la que se carga queda asociada a la carpeta (wp-config.php la usa la proxima vez)
    [[ "$4" =~ ^[A-Za-z0-9_-]+$ ]] && remember_project "$4" "$folder" "$(active_name)"
    load_project_domain "$folder" "$4" || return 1
    # Correo de pruebas: Mailpit con la version y la BBDD del proyecto al dia (sus plugins de correo, la
    # configuracion de la tienda)
    mailpit_sync
    local mdb
    mdb=$(mail_project_db "$folder" "$4") && db_names "$(active_dir)" | grep -qxF "$mdb" && mail_db "$mdb"
    # Imagenes de produccion (media-proyecto): las de este proyecto en el vhost de los proyectos
    media_sync || echo "Aviso: no se han podido poner en $link las imagenes de produccion de $folder"

    echo "Proyecto cargado: $link -> $folder$([ -L /opt/lampp ] && echo " ($(readlink /opt/lampp | sed 's:^/opt/::'))")"
}

