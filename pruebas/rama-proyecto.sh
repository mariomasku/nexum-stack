#!/bin/bash
# Rama de trabajo de un proyecto nuevo (1.57.15): gui-ramas-proyecto y rama-proyecto con un «origin» bare local
# con varias ramas, clonado en un htdocs de mentira (HOME y todo, en una carpeta temporal; sin red ni sudo).
# Lista la actual, las locales y las de origin (sin HEAD ni repetidas); cambia a una de origin (la local nueva,
# siguiendo a origin), crea una nueva (--nueva); con un nombre que no vale, una que no existe, cambios sin commit
# o una carpeta que no es de htdocs no cambia nada; sin ganchos. Y montar-proyecto --sin-bd (con funciones de
# mentira: sin clonar de verdad ni cargar): sin BBDD no crea ni sube ninguna, dos pasos, el aviso de un
# WordPress. Al final, lo de las ventanas (casilla «Sin base de datos», el diálogo de la rama y VS Code).
# Uso: rama-proyecto.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function project_branch() {' "$SRC" || { echo "  ok    (sin rama-proyecto)"; exit 0; }
command -v git > /dev/null || { echo "  ok    (sin git: no se prueba)"; exit 0; }
W=$(mktemp -d "$TMPBASE/w-rama.XXXXXX") || exit 1
trap 'chmod -R u+rwX "${W:?}" 2> /dev/null; rm -rf "${W:?}"' EXIT
MAC=0; grep -qE '^    BASE_DIR=(/Applications|/Library/Nexum)$' "$SRC" && MAC=1

extract "$SRC" project_git folder_owner branch_name_ok project_branch_list gui_project_branches project_branch \
    valid_project || exit 1

# El equipo de mentira: HOME (sin la configuracion de git de nadie) y htdocs
export HOME=$W/casa GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=Prueba GIT_AUTHOR_EMAIL=prueba@ejemplo.test
export GIT_COMMITTER_NAME=Prueba GIT_COMMITTER_EMAIL=prueba@ejemplo.test
mkdir -p "$HOME"
HTDOCS_DIR=$W/htdocs DRY=0
mkdir -p "$HTDOCS_DIR"
unset LVM_TAREA LVM_PROGRESO

# El «origin»: main, desarrollo y feature/carta (y su HEAD), clonado en htdocs/panaderia-luna
O=$W/origen.git S=$W/semilla
git init -q --bare "$O" && git -C "$O" symbolic-ref HEAD refs/heads/main
git init -q "$S" && git -C "$S" checkout -q -b main
echo '<?php echo "hola";' > "$S/index.php"
git -C "$S" add -A && git -C "$S" commit -qm inicio
git -C "$S" branch desarrollo && git -C "$S" branch feature/carta
git -C "$S" push -q "$O" main desarrollo feature/carta 2> /dev/null || { echo "  FALLA no se ha podido preparar el origin"; exit 1; }
P=$HTDOCS_DIR/panaderia-luna
git clone -q "$O" "$P" 2> /dev/null || { echo "  FALLA no se ha podido clonar"; exit 1; }
# (un gancho que no tiene que correr: rama-proyecto va sin ganchos)
printf '#!/bin/sh\ntouch "%s/gancho"\n' "$W" > "$P/.git/hooks/post-checkout"; chmod 755 "$P/.git/hooks/post-checkout"
head_of() { git -C "$P" symbolic-ref --short -q HEAD; }
run() { ( project_branch "$@" ) < /dev/null 2>&1; }

out=$(gui_project_branches panaderia-luna)
check "gui-ramas-proyecto: repositorio, la rama actual (la del clon) y sin cambios" 'grep -qx "G|1|" <<< "$out" && grep -qx "A|main" <<< "$out" && grep -qx "N|0" <<< "$out"'
check "... main local y en origin (una vez), desarrollo y feature/carta solo en origin" 'grep -qx "R|main|1|1" <<< "$out" && grep -qx "R|desarrollo|0|1" <<< "$out" && grep -qx "R|feature/carta|0|1" <<< "$out" && [ "$(grep -c "^R|" <<< "$out")" == 3 ]'
check "... sin HEAD ni origin/ delante" '! grep -q "HEAD\|origin/" <<< "$out"'

# A una rama que solo esta en origin: la local nueva, siguiendo a origin
out=$(run panaderia-luna desarrollo); rc=$?
check "rama-proyecto a una de origin: cambia y crea la local siguiendo a origin" '[ $rc -eq 0 ] && [ "$(head_of)" == desarrollo ] && [ "$(git -C "$P" rev-parse --abbrev-ref desarrollo@{u})" == origin/desarrollo ] && grep -q "siguiendo a origin/desarrollo" <<< "$out"' || echo "$out"
check "... sin correr los ganchos del repositorio" '[ ! -e "$W/gancho" ]'
out=$(gui_project_branches panaderia-luna)
check "gui-ramas-proyecto: ahora desarrollo es la actual, local y en origin" 'grep -qx "A|desarrollo" <<< "$out" && grep -qx "R|desarrollo|1|1" <<< "$out" && [ "$(grep -c "^R|" <<< "$out")" == 3 ]'
out=$(run panaderia-luna desarrollo); rc=$?
check "rama-proyecto a la que ya está: lo dice y no falla" '[ $rc -eq 0 ] && grep -q "ya está en la rama desarrollo" <<< "$out"'
out=$(run panaderia-luna main); rc=$?
check "rama-proyecto a una local: cambia" '[ $rc -eq 0 ] && [ "$(head_of)" == main ]'

# Rama nueva a partir de la actual
out=$(run panaderia-luna nueva-portada --nueva); rc=$?
check "rama-proyecto --nueva: la crea a partir de la actual y cambia a ella" '[ $rc -eq 0 ] && [ "$(head_of)" == nueva-portada ] && [ "$(git -C "$P" rev-parse nueva-portada)" == "$(git -C "$P" rev-parse main)" ]' || echo "$out"
out=$(run panaderia-luna feature/carta --nueva); rc=$?
check "rama-proyecto --nueva con una que ya está en origin: no" '[ $rc -ne 0 ] && grep -q "Ya hay una rama feature/carta en origin" <<< "$out" && [ "$(head_of)" == nueva-portada ] && ! git -C "$P" show-ref -q --verify refs/heads/feature/carta'
out=$(run panaderia-luna main --nueva); rc=$?
check "rama-proyecto --nueva con una local que ya existe: no" '[ $rc -ne 0 ] && [ "$(head_of)" == nueva-portada ]'

# Nombres que no valen y ramas que no existen: no cambia nada
for bad_name in "mal nombre" "-f" "a..b" "rama~1" "x|y" "HEAD" "fin." "con:dos"; do
    out=$(run panaderia-luna "$bad_name" --nueva); rc=$?
    check "rama-proyecto --nueva «$bad_name»: no vale y no cambia nada" '[ $rc -ne 0 ] && grep -q "no vale como nombre de rama" <<< "$out" && [ "$(head_of)" == nueva-portada ]'
done
out=$(run panaderia-luna no-existe); rc=$?
check "rama-proyecto a una que no existe (sin --nueva): no cambia nada" '[ $rc -ne 0 ] && grep -q "No hay ninguna rama no-existe" <<< "$out" && [ "$(head_of)" == nueva-portada ] && ! git -C "$P" show-ref -q --verify refs/heads/no-existe'
out=$(run panaderia-luna desarrollo --otra); rc=$?
check "rama-proyecto con una opción que no es --nueva: el uso" '[ $rc -ne 0 ] && grep -q "Uso: nexum rama-proyecto" <<< "$out" && [ "$(head_of)" == nueva-portada ]'

# Con cambios sin commit: no cambia nada (lo nuevo sin seguimiento no cuenta)
echo nuevo > "$P/nuevo.txt"
out=$(gui_project_branches panaderia-luna)
check "gui-ramas-proyecto: un fichero nuevo sin seguimiento no cuenta como cambio" 'grep -qx "N|0" <<< "$out"'
echo cambio >> "$P/index.php"
out=$(gui_project_branches panaderia-luna)
check "gui-ramas-proyecto: un cambio sin commit, contado" 'grep -qx "N|1" <<< "$out"'
out=$(run panaderia-luna main); rc=$?
check "rama-proyecto con cambios sin commit: no cambia y dice cuáles" '[ $rc -ne 0 ] && grep -q "cambio(s) sin commit" <<< "$out" && grep -q "index.php" <<< "$out" && [ "$(head_of)" == nueva-portada ] && grep -q cambio "$P/index.php"'
out=$(run panaderia-luna otra-mas --nueva); rc=$?
check "rama-proyecto --nueva con cambios sin commit: tampoco" '[ $rc -ne 0 ] && ! git -C "$P" show-ref -q --verify refs/heads/otra-mas'
git -C "$P" checkout -q -- index.php && rm -f "$P/nuevo.txt"

# En la simulacion, nada
out=$(DRY=1; run panaderia-luna main); rc=$?
check "rama-proyecto --simular: dice lo que haría y no cambia" '[ $rc -eq 0 ] && grep -q "\[simulacion\] git switch main" <<< "$out" && [ "$(head_of)" == nueva-portada ]'

# Carpetas que no son de htdocs, que no son un repositorio o un enlace que sale
mkdir -p "$W/fuera" "$HTDOCS_DIR/sin-git"
git clone -q "$O" "$W/fuera/repo" 2> /dev/null
ln -s "$W/fuera/repo" "$HTDOCS_DIR/enlace"
out=$(run ../fuera/repo desarrollo); rc=$?
check "rama-proyecto en una carpeta de fuera de htdocs (../): no" '[ $rc -ne 0 ] && [ "$(git -C "$W/fuera/repo" symbolic-ref --short HEAD)" == main ]'
out=$(run enlace desarrollo); rc=$?
check "rama-proyecto en un enlace de htdocs que lleva fuera: no" '[ $rc -ne 0 ] && grep -q "No existe el proyecto" <<< "$out" && [ "$(git -C "$W/fuera/repo" symbolic-ref --short HEAD)" == main ]'
out=$(gui_project_branches enlace); rc=$?
check "gui-ramas-proyecto en un enlace que lleva fuera: no" '[ $rc -ne 0 ] && ! grep -q "^R|" <<< "$out"'
out=$(run no-esta desarrollo); rc=$?
check "rama-proyecto en un proyecto que no existe: no" '[ $rc -ne 0 ] && grep -q "No existe el proyecto" <<< "$out"'
out=$(gui_project_branches sin-git)
check "gui-ramas-proyecto en una carpeta sin git: G|0 y sin ramas" 'grep -qx "G|0|" <<< "$out" && ! grep -q "^R|" <<< "$out"'
out=$(run sin-git main --nueva); rc=$?
check "rama-proyecto en una carpeta sin git: no" '[ $rc -ne 0 ] && grep -q "no es un repositorio git" <<< "$out" && [ ! -e "$HTDOCS_DIR/sin-git/.git" ]'

# Un repositorio sin ramas en origin (recien creado, sin remoto): la actual y se puede crear una nueva
mkdir -p "$HTDOCS_DIR/solo-local" && git -C "$HTDOCS_DIR/solo-local" init -q && git -C "$HTDOCS_DIR/solo-local" checkout -q -b main \
    && echo a > "$HTDOCS_DIR/solo-local/a" && git -C "$HTDOCS_DIR/solo-local" add -A && git -C "$HTDOCS_DIR/solo-local" commit -qm a
out=$(gui_project_branches solo-local)
check "gui-ramas-proyecto sin origin: solo la actual, local" 'grep -qx "A|main" <<< "$out" && [ "$(grep "^R|" <<< "$out")" == "R|main|1|0" ]'
out=$(run solo-local primera --nueva); rc=$?
check "rama-proyecto --nueva sin origin: la crea" '[ $rc -eq 0 ] && [ "$(git -C "$HTDOCS_DIR/solo-local" symbolic-ref --short HEAD)" == primera ]'

# Como root o en una carpeta de otro: no (con id de mentira)
out=$( id() { [ "$1" == -un ] && echo otro || command id "$@"; }; run panaderia-luna main ); rc=$?
check "rama-proyecto en una carpeta de otro usuario: no" '[ $rc -ne 0 ] && grep -q "no tuya" <<< "$out" && [ "$(head_of)" == nueva-portada ]'
# (como root no: EUID no se puede falsear aqui, se mira que lo compruebe)
check "rama-proyecto como root: no" 'grep -q "if \[ \"\${EUID:-\$(id -u)}\" -eq 0 \]; then" "$SRC" && grep -q "No se cambia de rama como root" "$SRC"'

# --- montar-proyecto --sin-bd (con funciones de mentira: el clon, la carga y la BBDD) ---
(
    extract "$SRC" mount_project git_url_ok valid_version_name is_wordpress || exit 1
    LOG_DIR=$W/log REPO_PROJECTS_FILE=$W/log/montados EMPTY_PROJECT=.lvm-sin-proyecto GIT_KNOWN_HOSTS="" DRY=0
    TEST_DIR=$W BASE_DIR=$W
    mkdir -p "$W/lampp-8.4" "$W/XAMPP-8.4"
    L=$W/hecho.log
    mktemp() { command mktemp "$W/conocidos.XXXXXX"; }
    task_plan() { shift; echo "PLAN $#" >> "$L"; }
    task_step() { :; }
    db_valid_name() { [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$ ]]; }
    db_names() { echo wp_otra; }
    data_owner() { :; }
    repo_ssh_url() { return 1; }
    repo_clone() { mkdir -p "$2" && echo "CLON $1" >> "$L"; [ -n "$CLONE_WP" ] && mkdir -p "$2/wp-includes"; return 0; }
    htdocs_close_world() { :; }
    is_prestashop() { return 1; }
    load_project() { echo "CARGAR [$1] [$2] [$3]" >> "$L"; }
    create_database() { echo "CREAR $*" >> "$L"; }
    import_database() { echo "IMPORTAR $*" >> "$L"; }
    load_project_domain() { echo "DOMINIO $*" >> "$L"; }
    mount() { : > "$L"; ( mount_project "$@" ) < /dev/null 2>&1; }

    out=$(mount https://github.com/ejemplo/panaderia-sol.git panaderia-sol 8.4 --sin-bd); rc=$?
    check "montar-proyecto --sin-bd: lo clona y lo carga sin base" '[ $rc -eq 0 ] && grep -qx "CLON https://github.com/ejemplo/panaderia-sol.git" "$L" && grep -qx "CARGAR \[panaderia-sol\] \[8.4\] \[\]" "$L"' || echo "$out"
    check "... no crea, no sube ni configura ninguna BBDD" '! grep -q "^CREAR\|^IMPORTAR\|^DOMINIO" "$L"'
    check "... dos pasos (1/2 y 2/2) y lo dice al acabar" 'grep -qx "PLAN 2" "$L" && grep -q "^1/2 " <<< "$out" && grep -q "^2/2 " <<< "$out" && grep -q "panaderia-sol en .*-8.4, sin BBDD$" <<< "$out" && ! grep -q "3/3\|Aviso" <<< "$out"'
    check "... la apunta como montada de un repositorio" 'grep -qx panaderia-sol "$REPO_PROJECTS_FILE"'
    out=$(CLONE_WP=1; mount https://github.com/ejemplo/panaderia-wp.git panaderia-wp 8.4 --sin-bd); rc=$?
    check "montar-proyecto --sin-bd de un WordPress: lo monta y avisa de que no abrirá hasta tener su BBDD" '[ $rc -eq 0 ] && grep -q "Aviso: es un WordPress: la web no funcionara hasta que tenga su BBDD" <<< "$out" && ! grep -q "^CREAR" "$L"'
    out=$(mount https://github.com/ejemplo/panaderia-dos.git panaderia-dos 8.4 --sin-bd "$W/volcado.sql"); rc=$?
    check "montar-proyecto --sin-bd con un volcado: no, sin clonar" '[ $rc -ne 0 ] && grep -q "Sin BBDD no se sube ningun volcado" <<< "$out" && ! grep -q CLON "$L" && [ ! -e "$HTDOCS_DIR/panaderia-dos" ]'
    out=$(mount https://github.com/ejemplo/panaderia-dos.git panaderia-dos 8.4); rc=$?
    check "montar-proyecto sin base ni --sin-bd: el uso, con las dos formas" '[ $rc -ne 0 ] && grep -q "<base de datos> \[volcado\]" <<< "$out" && grep -q "<version> --sin-bd" <<< "$out" && ! grep -q CLON "$L"'
    out=$(mount https://github.com/ejemplo/panaderia-tres.git panaderia-tres 8.4 wp_panaderia_tres); rc=$?
    check "montar-proyecto con base (como siempre): tres pasos y crea la BBDD" '[ $rc -eq 0 ] && grep -qx "PLAN 3" "$L" && grep -qx "CARGAR \[panaderia-tres\] \[8.4\] \[wp_panaderia_tres\]" "$L" && grep -qx "CREAR wp_panaderia_tres" "$L" && grep -q "^3/3 " <<< "$out"'
    out=$(mount https://github.com/ejemplo/panaderia-cua.git panaderia-cua 8.4 wp_otra); rc=$?
    check "montar-proyecto con una base que ya existe: no (sigue igual)" '[ $rc -ne 0 ] && grep -q "Ya hay una BBDD wp_otra" <<< "$out" && ! grep -q CLON "$L"'
    out=$(DRY=1; mount https://github.com/ejemplo/panaderia-cin.git panaderia-cin 8.4 --sin-bd); rc=$?
    check "montar-proyecto --sin-bd --simular: dos pasos, sin BBDD, sin clonar" '[ $rc -eq 0 ] && grep -q "2/2 \[simulacion\] cargar-proyecto panaderia-cin 8.4 (sin BBDD)" <<< "$out" && ! grep -q "crear-bd\|importar-bd\|3/3" <<< "$out" && ! grep -q CLON "$L"'
    exit $fail
) || fail=1

# Las órdenes nuevas no piden la contraseña de administrador (tareas de la ventana)
check "rama-proyecto sin contraseña de administrador (gui-ramas-proyecto va con las gui-*)" 'grep -q "^        tunel-abrir|tunel-instalar|tunel-cerrar|repo-traer|rama-proyecto|borrar-bd|borrar-bd-marcadas|marcar-bd) ;;" "$SRC" && grep -q "^    rama-proyecto) project_branch \"\$2\" \"\$3\" \"\$4\" ;;" "$SRC" && grep -q "^    gui-ramas-proyecto) gui_project_branches \"\$2\" ;;" "$SRC"'
check "ayuda: rama-proyecto, gui-ramas-proyecto y montar-proyecto --sin-bd" 'grep -q "^#   nexum rama-proyecto <carpeta> <rama> \[--nueva\]" "$SRC" && grep -q "^#   nexum gui-ramas-proyecto <carpeta>" "$SRC" && grep -q "^#   nexum montar-proyecto <url de git> <carpeta> <version> --sin-bd" "$SRC"'

# Las ventanas
if grep -q "LVM_SWIFT" "$SRC"; then
    check "Mac: casilla «Sin base de datos» en Nuevo proyecto, que manda --sin-bd" 'grep -q "Toggle(\"Sin base de datos\", isOn: \$model.npNoDb)" "$SRC" && grep -q "args.append(\"--sin-bd\")" "$SRC"'
    check "Mac: sin base, el aviso de WordPress y PrestaShop" 'grep -q "la web no funcionará hasta que tenga su BBDD" "$SRC"'
    check "Mac: al acabar de montarlo, el diálogo de la rama (gui-ramas-proyecto)" 'grep -q "self.askBranch(folder)" "$SRC" && grep -q "runQuick(\[\"gui-ramas-proyecto\", folder\])" "$SRC" && grep -q "alert.messageText = \"¿En qué rama empiezas a trabajar?\"" "$SRC"'
    check "Mac: Empezar a trabajar y Más tarde; la rama con rama-proyecto y luego VS Code" 'grep -q "addButton(withTitle: \"Empezar a trabajar\")" "$SRC" && grep -q "addButton(withTitle: \"Más tarde\")" "$SRC" && grep -q "\[\"rama-proyecto\", folder, branch\]" "$SRC" && grep -q "if code { openInVSCode(path) }" "$SRC"'
    check "Mac: la casilla de VS Code, marcada si está instalado" 'grep -q "NSButton(checkboxWithTitle: \"Abrir en Visual Studio Code\"" "$SRC" && grep -q "vsc.state = hasCode ? .on : .off" "$SRC"'
else
    check "Linux: casilla «Sin base de datos» en Nuevo proyecto, que manda --sin-bd" 'grep -q "w\[\"nodb\"\] = Gtk.CheckButton(label=\"Sin base de datos\")" "$SRC" && grep -q "\[\"--sin-bd\"\] if nodb" "$SRC"'
    check "Linux: sin base, el aviso de WordPress y PrestaShop" 'grep -q "la web no funcionará hasta que tenga su BBDD" "$SRC"'
    check "Linux: al acabar de montarlo, el diálogo de la rama (gui-ramas-proyecto)" 'grep -q "self.nv_branch_ask(folder)" "$SRC" && grep -q "run_quick(\[\"gui-ramas-proyecto\", folder\], got)" "$SRC" && grep -q "text=\"¿En qué rama empiezas a trabajar?\")" "$SRC"'
    check "Linux: Empezar a trabajar y Más tarde; la rama con rama-proyecto y luego VS Code" 'grep -q "add_button(\"Empezar a trabajar\"" "$SRC" && grep -q "add_button(\"Más tarde\"" "$SRC" && grep -q "\[\"rama-proyecto\", folder, branch\]" "$SRC" && grep -q "self.open_in_vscode(path)" "$SRC"'
    check "Linux: la casilla de VS Code, marcada si está instalado" 'grep -q "Gtk.CheckButton(label=\"Abrir en Visual Studio Code\", active=has_code" "$SRC"'
    BN=$(python3 -c "import re, subprocess
$(awk '/^def branch_name_ok\(name\):/,/^$/' "$SRC")
print(branch_name_ok('nueva-portada'), branch_name_ok('feature/carta'), branch_name_ok('mal nombre'), branch_name_ok('-f'), branch_name_ok('a..b'), branch_name_ok('x|y'), branch_name_ok(''))" 2>&1)
    check "Linux: branch_name_ok como git check-ref-format --branch" '[ "$BN" == "True True False False False False False" ]' || echo "$BN"
fi
exit $fail
