#!/bin/bash
# Montar un proyecto desde un repositorio privado (Linux 1.56.3, Mac 1.40.1): si una direccion https de
# GitHub, GitLab o Bitbucket no se puede clonar (pide usuario y contraseña, y no se preguntan), se prueba
# sola la misma por SSH. Con otros servidores, no. Con un git falso. Uso: clonar-ssh.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-clonar.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function repo_ssh_url() {' "$SRC" || { echo "  ok    (sin probar por SSH)"; exit 0; }
extract "$SRC" repo_ssh_url repo_clone mount_project git_url_ok || exit 1

# Direcciones
check "github https -> ssh" '[ "$(repo_ssh_url https://github.com/hexer-dev/dob-wordpress-x)" == git@github.com:hexer-dev/dob-wordpress-x.git ]'
check "con .git y con / al final, igual" '[ "$(repo_ssh_url https://github.com/u/r.git)" == git@github.com:u/r.git ] && [ "$(repo_ssh_url https://github.com/u/r/)" == git@github.com:u/r.git ]'
check "gitlab con subgrupos y bitbucket" '[ "$(repo_ssh_url https://gitlab.com/grupo/sub/r)" == git@gitlab.com:grupo/sub/r.git ] && [ "$(repo_ssh_url https://bitbucket.org/u/r)" == git@bitbucket.org:u/r.git ]'
check "otro servidor, ya ssh, sin usuario o con cosas raras: no" '! repo_ssh_url https://git.empresa.es/u/r && ! repo_ssh_url git@github.com:u/r.git && ! repo_ssh_url https://github.com/r && ! repo_ssh_url "https://github.com/u/r;x" && ! repo_ssh_url https://github.com/u/../r'

# Montar: git falso (https falla como un privado; ssh clona)
HTDOCS_DIR=$W/htdocs TEST_DIR=$W DRY=0 BASE_DIR=$W EMPTY_PROJECT=.lvm-sin-proyecto REPO_PROJECTS_FILE=$W/montados GIT_KNOWN_HOSTS=x
mkdir -p "$HTDOCS_DIR" "$W/lampp-8.4" "$W/XAMPP-8.4" "$W/bin"
cat > "$W/bin/git" << 'EOF'
#!/bin/bash
echo "$*" >> "$(dirname "$0")/../git.log"
for a in "$@"; do last2=$last; last=$a; done
case $last2 in
    https://*) echo "fatal: could not read Username for 'https://github.com': terminal prompts disabled"; exit 128 ;;
    git@*) mkdir -p "$last"; echo "Clonando en '$last'..." ;;
esac
EOF
chmod 755 "$W/bin/git"
PATH=$W/bin:$PATH
no_tty() { "$@"; }
valid_version_name() { true; }
data_owner() { echo 8.4; }
db_names() { :; }
db_valid_name() { true; }
htdocs_close_world() { :; }
load_project() { echo "cargar $*"; return 1; }
out=$(mount_project https://github.com/hexer-dev/privado privado 8.4 wp_privado 2>&1)
check "privado por https: se prueba por SSH y se clona" 'grep -q "se prueba por SSH, git@github.com:hexer-dev/privado.git" <<< "$out" && [ -d "$HTDOCS_DIR/privado" ] && grep -q "cargar privado 8.4 wp_privado" <<< "$out" && ! grep -q "No se ha podido clonar" <<< "$out"'
check "por SSH, igual de cerrado (sin terminal, sin ganchos ni credenciales guardadas)" 'grep -q "core.hooksPath=/dev/null -c credential.helper= .* clone --no-recurse-submodules -- git@github.com:hexer-dev/privado.git" "$W/git.log"'
out=$(mount_project https://git.empresa.es/u/privado otro 8.4 wp_otro 2>&1)
check "otro servidor: no se prueba por SSH y lo dice" '! grep -q "se prueba por SSH" <<< "$out" && grep -q "No se ha podido clonar" <<< "$out" && [ ! -e "$HTDOCS_DIR/otro" ]'
exit $fail
