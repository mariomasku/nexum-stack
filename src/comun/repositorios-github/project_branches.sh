# La rama de trabajo de un proyecto de htdocs (al montarlo, la ventana pregunta en cual se empieza):
#   gui-ramas-proyecto <carpeta>             solo lee: las ramas para el dialogo
#   rama-proyecto <carpeta> <rama> [--nueva] cambia a esa rama (o la crea a partir de la actual)
# Con tu usuario, el dueño de la carpeta (el clon de montar-proyecto es tuyo): ni como root ni en una
# carpeta de otro. Sin ganchos ni ayudantes de la configuracion del repositorio y sin red

# git en la carpeta de un proyecto, sin preguntas, sin ganchos y sin los filtros de git-lfs (su
# .lfsconfig llevaria las descargas a otro servidor): project_git <carpeta> <orden de git...>
function project_git() {
    local dir=$1
    shift
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false GIT_LFS_SKIP_SMUDGE=1 \
        git -C "$dir" -c core.hooksPath=/dev/null -c core.fsmonitor=false -c credential.helper= \
            -c filter.lfs.process= -c filter.lfs.smudge= -c filter.lfs.required=false "$@" < /dev/null
}

# El dueño de una carpeta (en Linux y en el Mac)
function folder_owner() {
    stat -c %U "$1" 2> /dev/null || stat -f %Su "$1" 2> /dev/null
}

# ¿Nombre de rama que se puede crear? (el de git check-ref-format --branch, sin - al principio, que git
# tomaria como opcion, ni | , que separa los campos de gui-ramas-proyecto)
function branch_name_ok() {
    [ -n "$1" ] && [[ "$1" != -* ]] && [[ "$1" != *"|"* ]] && [ "$1" != HEAD ] \
        && git check-ref-format --branch "$1" > /dev/null 2>&1
}

# Las ramas de la carpeta: una por linea, <rama>|<local 1/0>|<en origin 1/0> (sin origin/HEAD ni
# repetidas: la que esta en los dos sitios, una sola vez)
function project_branch_list() {
    project_git "$1" for-each-ref --format='%(refname)' refs/heads refs/remotes/origin 2> /dev/null | awk '
        /^refs\/heads\// { b = substr($0, 12); if (b ~ /\|/) next; if (!(b in seen)) order[++n] = b; seen[b] = 1; loc[b] = 1; next }
        /^refs\/remotes\/origin\// { b = substr($0, 21); if (b == "HEAD" || b ~ /\|/) next
            if (!(b in seen)) order[++n] = b; seen[b] = 1; rem[b] = 1 }
        END { for (i = 1; i <= n; i++) { b = order[i]; print b "|" (b in loc ? 1 : 0) "|" (b in rem ? 1 : 0) } }'
}

# gui-ramas-proyecto <carpeta>: lo que necesita el dialogo «¿En qué rama empiezas a trabajar?»
#   G|<0 no es un repositorio git, 1 si, 2 no se ha podido leer>|<el error>
#   A|<rama actual>                      (vacia si no esta en ninguna)
#   N|<cambios sin commit>               (de lo que ya esta en git: lo nuevo sin seguimiento no cuenta)
#   R|<rama>|<local 1/0>|<en origin 1/0> una por rama
function gui_project_branches() {
    local folder=${1%/} dir out n=0
    valid_project "$folder" > /dev/null || { echo "G|2|No existe el proyecto $folder"; return 1; }
    dir=$HTDOCS_DIR/$folder
    if [ ! -e "$dir/.git" ] || ! command -v git > /dev/null; then
        echo "G|0|"
        return 0
    fi
    if ! out=$(GIT_OPTIONAL_LOCKS=0 project_git "$dir" status --porcelain --untracked-files=no 2>&1); then
        echo "G|2|$(head -1 <<< "$out" | tr '|' ' ')"
        return 0
    fi
    [ -n "$out" ] && n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
    echo "G|1|"
    echo "A|$(project_git "$dir" symbolic-ref --short -q HEAD 2> /dev/null | tr '|' '_')"
    echo "N|$n"
    project_branch_list "$dir" | sed 's/^/R|/'
    return 0
}

# rama-proyecto <carpeta> <rama> [--nueva]: cambia el proyecto a esa rama con git switch. Una rama que
# solo esta en origin se crea en local siguiendo a la de origin; con --nueva, se crea a partir de la
# actual (y no puede existir ya). Con cambios sin commit no se cambia nada
function project_branch() {
    local folder=${1%/} branch=$2 new=0 dir out me owner local_has remote_has
    [ "$3" == --nueva ] && new=1
    if [ -z "$folder" ] || [ -z "$branch" ] || { [ -n "$3" ] && [ $new -eq 0 ]; }; then
        echo "Uso: nexum rama-proyecto <carpeta> <rama> [--nueva]"

        return 1
    fi
    valid_project "$folder" || return 1
    dir=$HTDOCS_DIR/$folder
    if ! command -v git > /dev/null; then
        echo "Hace falta git para cambiar de rama"

        return 1
    fi
    if [ ! -e "$dir/.git" ]; then
        echo "$folder no es un repositorio git: no tiene ramas"

        return 1
    fi
    if ! branch_name_ok "$branch"; then
        echo "«$branch» no vale como nombre de rama (git check-ref-format): sin espacios ni ~ ^ : ? * [ \\,"
        echo "sin .. ni @{ y sin - al principio"

        return 1
    fi
    me=$(id -un)
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        echo "No se cambia de rama como root: hazlo con tu usuario (el dueño de la carpeta)."

        return 1
    fi
    owner=$(folder_owner "$dir")
    if [ "$owner" != "$me" ]; then
        echo "La carpeta $dir es de ${owner:-otro usuario}, no tuya: cambia de rama con su usuario."

        return 1
    fi
    if ! out=$(GIT_OPTIONAL_LOCKS=0 project_git "$dir" status --porcelain --untracked-files=no 2>&1); then
        echo "git no ha podido leer $dir: $(head -1 <<< "$out")"

        return 1
    fi
    if [ -n "$out" ]; then
        echo "$folder tiene $(printf '%s\n' "$out" | wc -l | tr -d ' ') cambio(s) sin commit: no se cambia de rama."
        printf '%s\n' "$out" | head -8 | sed 's/^/  /'
        echo "Haz commit de esos cambios (o descártalos) y vuelve a intentarlo."

        return 1
    fi
    project_git "$dir" show-ref --verify -q "refs/heads/$branch" && local_has=1
    project_git "$dir" show-ref --verify -q "refs/remotes/origin/$branch" && remote_has=1
    if [ $new -eq 1 ] && { [ -n "$local_has" ] || [ -n "$remote_has" ]; }; then
        echo "Ya hay una rama $branch$([ -n "$remote_has" ] && [ -z "$local_has" ] && echo " en origin"): elígela de la lista en vez de crearla"

        return 1
    fi
    if [ $new -eq 0 ] && [ -z "$local_has" ] && [ -z "$remote_has" ]; then
        echo "No hay ninguna rama $branch (ni en local ni en origin). Para crearla: nexum rama-proyecto $folder $branch --nueva"

        return 1
    fi
    if [ $new -eq 0 ] && [ "$(project_git "$dir" symbolic-ref --short -q HEAD 2> /dev/null)" == "$branch" ]; then
        echo "$folder ya está en la rama $branch"

        return 0
    fi
    if [ $new -eq 1 ]; then
        set -- switch -c "$branch"
    elif [ -n "$local_has" ]; then
        set -- switch "$branch"
    else
        # (solo en origin: la local nueva, siguiendo a la de origin)
        set -- switch -c "$branch" --track "origin/$branch"
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] git $* (en $dir, con tu usuario)"

        return 0
    fi
    if ! out=$(project_git "$dir" "$@" 2>&1); then
        echo "git no ha podido cambiar a la rama $branch:"
        printf '%s\n' "$out" | head -8 | sed 's/^/  /'

        return 1
    fi
    if [ $new -eq 1 ]; then
        echo "Rama nueva $branch en $folder, a partir de la que tenía"
    elif [ -n "$local_has" ]; then
        echo "$folder está en la rama $branch"
    else
        echo "$folder está en la rama $branch (nueva en local, siguiendo a origin/$branch)"
    fi
}
