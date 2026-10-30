#!/bin/bash
# Pestaña Repositorios (Linux 1.56.8, Mac 1.40.1): la conexion con GitHub (token en el llavero, por la
# entrada; o la sesion de gh), la cuenta y los prefijos, la lista (con sus paginas, sin archivados, por
# prefijos, y si ya esta clonado), su cache, y clonar por SSH o traer los cambios con git pull. Sin
# Internet: GitHub, el llavero y git, falsos. Uso: repos.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-repos.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function repos_list() {' "$SRC" || { echo "  ok    (sin la pestaña Repositorios)"; exit 0; }
extract "$SRC" github_conf github_conf_set github_token gh_token github_api github_connect github_disconnect \
    github_command repo_clones repos_list repos_rows repo_fetch || exit 1
MAC=0
grep -q "LVM_SWIFT" "$SRC" && MAC=1
DRY=0 HTDOCS_DIR=$W/htdocs GITHUB_CONF_FILE=$W/conf/github GITHUB_KEYRING_SERVICE=nexum-dev-stack
GITHUB_DEFAULT_PREFIXES="dob-wordpress- dob-prestashop-" REPOS_CACHE_FILE=$W/conf/repos-github
REPO_PROJECTS_FILE=$W/conf/montados GIT_KNOWN_HOSTS="github.com ssh-ed25519 AAAA"
mkdir -p "$HTDOCS_DIR"
# El llavero falso: lo que le llega por la entrada y por la linea de ordenes, por separado
secret-tool() { echo "ARGS $*" >> "$W/llavero.log"
    case $1 in store) cat > "$W/llavero" ;; lookup) cat "$W/llavero" 2> /dev/null ;; clear) rm -f "$W/llavero" ;; esac; }
security() { echo "ARGS $*" >> "$W/llavero.log"
    case $1 in -i) sed -n 's/.* -w \([^ ]*\)$/\1/p' > "$W/llavero" ;; find-generic-password) cat "$W/llavero" 2> /dev/null ;;
               delete-generic-password) rm -f "$W/llavero" ;; esac; }
timeout() { shift; "$@"; }
# GitHub falso: curl con sus respuestas por direccion (y el token que le llega, por la entrada)
curl() { local url="${@: -1}" hdr=/dev/null a prev=""
    for a in "$@"; do [ "$prev" == -D ] && hdr=$a; prev=$a; done
    cat > "$W/curl-entrada"; echo "ARGS $*" >> "$W/curl.log"
    grep -q "Bearer tok_bueno_1234567890abcdef" "$W/curl-entrada" || return 22
    case $url in
        */user) echo '{"login": "yo"}' ;;
        */users/hexer) echo '{"type": "Organization"}' ;;
        */users/yo) echo '{"type": "User"}' ;;
        */orgs/hexer/repos?*page=2) : > "$hdr"; cat "$W/pagina2.json" ;;
        */orgs/hexer/repos?*) printf 'link: <https://api.github.com/orgs/hexer/repos?type=all&sort=pushed&per_page=100&page=2>; rel="next"\r\n' > "$hdr"; cat "$W/pagina1.json" ;;
        *) return 22 ;;
    esac; }
cat > "$W/pagina1.json" << 'J'
[{"full_name": "hexer/dob-wordpress-uno", "name": "dob-wordpress-uno", "private": true, "archived": false, "pushed_at": "2026-10-28T10:00:00Z", "default_branch": "master", "homepage": "https://uno.es", "description": "La | web de uno", "owner": {"login": "hexer"}},
 {"full_name": "hexer/dob-prestashop-dos", "name": "dob-prestashop-dos", "private": true, "archived": false, "pushed_at": "2026-10-27T10:00:00Z", "default_branch": "main", "homepage": null, "description": null, "owner": {"login": "hexer"}},
 {"full_name": "hexer/dob-wordpress-viejo", "name": "dob-wordpress-viejo", "private": false, "archived": true, "pushed_at": "2020-01-01T10:00:00Z", "default_branch": "master", "homepage": "", "description": "", "owner": {"login": "hexer"}}]
J
cat > "$W/pagina2.json" << 'J'
[{"full_name": "hexer/herramientas", "name": "herramientas", "private": false, "archived": false, "pushed_at": "2026-10-01T10:00:00Z", "default_branch": "main", "homepage": "", "description": "Scripts", "owner": {"login": "hexer"}},
 {"full_name": "hexer/dob-wordpress-tres", "name": "dob-wordpress-tres", "private": true, "archived": false, "pushed_at": "2026-09-01T10:00:00Z", "default_branch": "master", "homepage": "", "description": "", "owner": {"login": "hexer"}}]
J

# Configuracion
check "sin configurar: los prefijos de DevHub, sin cuenta ni conexion" '[ "$(github_conf PREFIJOS)" == "dob-wordpress- dob-prestashop-" ] && [ -z "$(github_conf CUENTA)" ] && [ -z "$(github_token)" ]'
check "la cuenta y los prefijos: solo nombres validos" '! github_command cuenta "a b" > /dev/null && ! github_command prefijos "ok mal/o" > /dev/null && github_command cuenta hexer > /dev/null && github_command prefijos "dob-wordpress- dob-prestashop- dob-shopify-" > /dev/null && [ "$(github_conf PREFIJOS)" == "dob-wordpress- dob-prestashop- dob-shopify-" ]'
check "el fichero, solo tuyo" '[ "$(stat -c %a "$GITHUB_CONF_FILE" 2> /dev/null || stat -f %Lp "$GITHUB_CONF_FILE")" == 600 ]'
check "prefijos vacios: todos" 'github_command prefijos "" > /dev/null && [ -z "$(github_conf PREFIJOS)" ] && github_command prefijos "dob-wordpress- dob-prestashop-" > /dev/null'

# Conectar con un token (por la entrada)
out=$(echo "no vale" | github_connect 2>&1); rc=$?
check "conectar: algo que no es un token, no" '[ $rc -ne 0 ] && grep -q "no parece un token" <<< "$out" && [ ! -e "$W/llavero" ]'
out=$(echo "tok_malo_1234567890abcdefgh" | github_connect 2>&1); rc=$?
check "conectar: un token que GitHub no acepta, no se guarda" '[ $rc -ne 0 ] && grep -q "no acepta" <<< "$out" && [ ! -e "$W/llavero" ]'
out=$(echo "tok_bueno_1234567890abcdef" | github_connect 2>&1); rc=$?
check "conectar: con el bueno, lo dice y va al llavero" '[ $rc -eq 0 ] && grep -q "Conectado a GitHub como yo" <<< "$out" && grep -q tok_bueno "$W/llavero" && [ "$(github_conf ORIGEN)" == llavero ]'
check "el token nunca en la linea de ordenes (ni del llavero ni de curl) ni en un fichero de Nexum" '! grep -q tok_bueno "$W/llavero.log" "$W/curl.log" && ! grep -rq tok_bueno "$W/conf"'
check "cuenta: tambien su direccion de GitHub o con @ (se queda el nombre)" 'github_command cuenta "https://github.com/hexer/" > /dev/null && [ "$(github_conf CUENTA)" == hexer ] && github_command cuenta "@hexer" > /dev/null && [ "$(github_conf CUENTA)" == hexer ]'
out=$(github_command cuenta noexiste 2>&1); rc=$?
check "cuenta: una que no existe en GitHub, no se guarda y se dice" '[ $rc -ne 0 ] && grep -q "no hay ninguna organización ni cuenta noexiste" <<< "$out" && [ "$(github_conf CUENTA)" == hexer ]'
check "github estado: conectado, quien, como, la cuenta y los prefijos" '[ "$(github_command estado)" == "G|1|yo|llavero|hexer|dob-wordpress- dob-prestashop-" ]'

# La lista
out=$(repos_list); rc=$?
check "lista: las dos paginas, sin los archivados y solo los de los prefijos" '[ $rc -eq 0 ] && grep -qx "C|yo|hexer|Organization|4|3" <<< "$out" && grep -q "^R|hexer/dob-wordpress-tres|" <<< "$out" && ! grep -q "herramientas\|viejo" <<< "$out"'
check "lista: cada uno con lo suyo (privado, fecha, rama, prefijo, web; sin | en la descripcion)" 'grep -qx "R|hexer/dob-wordpress-uno|dob-wordpress-uno|1|2026-10-28|master|dob-wordpress-|https://uno.es|La web de uno|nuevo|" <<< "$out"'
check "mostrar todos" 'repos_list --todos | grep -q "^R|hexer/herramientas|"'
check "cache: solo tuya, y la lista sin preguntar a GitHub" '[ "$(stat -c %a "$REPOS_CACHE_FILE" 2> /dev/null || stat -f %Lp "$REPOS_CACHE_FILE")" == 600 ] && : > "$W/curl.log" && repos_list --cache | grep -qx "C|yo|hexer|Organization|4|3" && ! grep -q "/repos" "$W/curl.log"'
check "cache de otra cuenta: no vale" 'github_command cuenta otra > /dev/null; [ -z "$(repos_list --cache)" ]; github_command cuenta hexer > /dev/null'
# Ya clonados (origin por https o por SSH, en minusculas o no) y una carpeta con su nombre que es otra cosa
mkdir -p "$HTDOCS_DIR/uno-local/.git" "$HTDOCS_DIR/dos/.git" "$HTDOCS_DIR/dob-wordpress-tres"
printf '[remote "origin"]\n\turl = https://github.com/Hexer/dob-wordpress-uno.git\n' > "$HTDOCS_DIR/uno-local/.git/config"
printf '[core]\n\tbare = false\n[remote "origin"]\n\turl = git@github.com:hexer/dob-prestashop-dos.git\n\tfetch = +refs/heads/*\n' > "$HTDOCS_DIR/dos/.git/config"
out=$(repos_list --cache)
check "ya clonado: en que carpeta (por https o por SSH)" 'grep -q "^R|hexer/dob-wordpress-uno|.*|clonado|uno-local$" <<< "$out" && grep -q "^R|hexer/dob-prestashop-dos|.*|clonado|dos$" <<< "$out"'
check "una carpeta con su nombre que no es ese repositorio: ocupado" 'grep -q "^R|hexer/dob-wordpress-tres|.*|ocupado|dob-wordpress-tres$" <<< "$out"'
github_command cuenta yo > /dev/null
check "la cuenta de quien conecta (User): tambien sus privados" ': > "$W/curl.log"; repos_list > /dev/null; grep -q "/user/repos?affiliation=owner" "$W/curl.log"'
github_command cuenta hexer > /dev/null

# Clonar y traer cambios (git falso)
repo_clone() { echo "clone $*" >> "$W/git.log"; mkdir -p "$2/.git"; printf '[remote "origin"]\n\turl = %s\n' "$1" > "$2/.git/config"; }
htdocs_close_world() { :; }
PULL_RC=0
no_tty() { echo "no_tty $*" >> "$W/git.log"; [ "$*" == *" merge "* ] && return 0; return $PULL_RC; }
git() { case "$*" in *"symbolic-ref"*) echo master ;; *"remote.origin.url"*) sed -n 's/^\turl = //p' "${2}/.git/config" ;; *"branch.master.merge"*) echo refs/heads/master ;; *"merge --abort"*) echo abort >> "$W/git.log" ;; esac; }
out=$(repo_fetch "hexer/dob-wordpress-nuevo" 2>&1); rc=$?
check "clonar: por SSH, en htdocs con su nombre, y apuntado como de repositorio" '[ $rc -eq 0 ] && grep -q "^clone git@github.com:hexer/dob-wordpress-nuevo.git $HTDOCS_DIR/dob-wordpress-nuevo " "$W/git.log" && grep -qx dob-wordpress-nuevo "$REPO_PROJECTS_FILE"'
check "clonar: nombres raros, no" '! repo_fetch "hexer/../x" > /dev/null 2>&1 && ! repo_fetch "-x/y" > /dev/null 2>&1 && ! repo_fetch "solo" > /dev/null 2>&1'
out=$(repo_fetch "hexer/dob-wordpress-tres" 2>&1); rc=$?
check "clonar: con una carpeta de su nombre que es otra cosa, no se toca" '[ $rc -ne 0 ] && grep -q "no es un clon" <<< "$out"'
out=$(repo_fetch "Hexer/dob-wordpress-uno" 2>&1); rc=$?
check "ya clonado: lo dice (EXISTE, para preguntar) y no hace nada" '[ $rc -eq 3 ] && grep -qx "EXISTE|uno-local" <<< "$out"'
: > "$W/git.log"
out=$(repo_fetch "hexer/dob-wordpress-uno" --actualizar 2>&1); rc=$?
check "aplastar: git pull en su carpeta (origin https: por SSH, su rama), sin ganchos ni preguntas" '[ $rc -eq 0 ] && grep -q "no_tty git -C $HTDOCS_DIR/uno-local -c core.hooksPath=/dev/null .* pull --no-rebase --no-edit git@github.com:hexer/dob-wordpress-uno.git master" "$W/git.log"'
: > "$W/git.log"
repo_fetch "hexer/dob-prestashop-dos" --actualizar > /dev/null 2>&1
check "aplastar: origin ya por SSH, git pull normal" 'grep -q "pull --no-rebase --no-edit$" "$W/git.log"'
PULL_RC=1; mkdir -p "$HTDOCS_DIR/dos/.git"; touch "$HTDOCS_DIR/dos/.git/MERGE_HEAD"
out=$(repo_fetch "hexer/dob-prestashop-dos" --actualizar 2>&1); rc=$?
check "si choca con lo tuyo: se deshace, no se toca nada y se dice" '[ $rc -ne 0 ] && grep -q "No se ha tocado nada" <<< "$out" && grep -qx abort "$W/git.log"'

# Desconectar
github_disconnect > /dev/null
check "desconectar: fuera del llavero" '[ ! -e "$W/llavero" ] && [ -z "$(github_token)" ] && repos_list | grep -q "^E|GitHub no está conectado"'

# La ventana
if [ $MAC -eq 1 ]; then
    check "ventana (Mac): la pestaña, su apartado en Configuración y el token por la entrada" 'grep -q "(\"repos\", \"Repositorios\", \"logo:github\")" "$SRC" && grep -q "case \"repos\": ReposView()" "$SRC" && grep -q "^            GitHubCard()$" "$SRC" && grep -q "runQuick(\[\"github-conectar\"\], input:" "$SRC"'
    check "ventana (Mac): si la cuenta no vale, se dice en una ventana y lo escrito se queda" 'grep -q "message(\"No se ha guardado\"" "$SRC"'
    check "ventana (Mac): el logotipo de GitHub detrás de Clonar o Traer cambios, a su repositorio" 'grep -q "Button(action: { openURL(\"https://github.com/\" + item.full) })" "$SRC" && grep -q ".tip(\"Abrir en GitHub (https://github.com/\" + item.full" "$SRC"'
    check "ventana (Mac): ya clonado, se pregunta si aplastar antes de git pull" 'grep -q "guard confirm(\"¿Aplastar" "$SRC" && grep -q "args.append(\"--actualizar\")" "$SRC"'
else
    check "ventana: la pestaña, su apartado en Configuración y el token por la entrada" 'grep -q "(\"repos\", \"Repositorios\", \"logo:github\")," "$SRC" && grep -q "        self.nv_github_tools()" "$SRC" && grep -q "run_quick_input(\[\"github-conectar\"\], token" "$SRC"'
    check "ventana: si la cuenta no vale, se dice en una ventana y lo escrito se queda" 'grep -q "self.nv_github_saved))" "$SRC" && grep -q "message(self.win, \"No se ha guardado\"" "$SRC"'
    check "ventana: el logotipo de GitHub detrás de Clonar o Traer cambios, a su repositorio" 'grep -q "gh.add(MonoLogo(\"github\", 18))" "$SRC" && grep -q "self.open_uri(\"https://github.com/%s\" % repo\[\"full\"\])" "$SRC"'
    check "ventana: ya clonado, se pregunta si aplastar antes de git pull" 'grep -q "if not confirm(self.win, \"¿Aplastar" "$SRC" && grep -q "\[\"repo-traer\", repo\[\"full\"\], \"--actualizar\"\]" "$SRC"'
fi
exit $fail
