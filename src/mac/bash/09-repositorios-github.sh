# ===========================================================================
# Repositorios de GitHub (pestaña Repositorios)
# ===========================================================================
# Los repositorios de una organizacion o cuenta de GitHub, para clonarlos por SSH en htdocs (o, si ya
# estan, traer sus cambios con git pull). Como DevHub: un token de GitHub (o la sesion de gh) solo para
# leer la lista, y los prefijos de los nombres que se ven (dob-wordpress-, dob-prestashop-...). El token
# va en el Llavero, no en un fichero; GITHUB_CONF_FILE (solo tuyo) lleva:
#   CUENTA=   la organizacion o cuenta cuyos repositorios se ven
#   PREFIJOS= los prefijos de los nombres que se ven, separados por espacios (vacio: todos)
#   ORIGEN=   llavero (el token guardado) o gh (la sesion de la herramienta de GitHub)
GITHUB_CONF_FILE=$HOME/.lvm-instalador/github
GITHUB_KEYRING_SERVICE=nexum-dev-stack
GITHUB_DEFAULT_PREFIXES="dob-wordpress- dob-prestashop-"

#@incluir comun/repositorios-github/github_conf.sh
# El token con el que se lee la lista (nada si no hay)
function github_token() {
    case $(github_conf ORIGEN) in
        llavero) security find-generic-password -s "$GITHUB_KEYRING_SERVICE" -a github -w 2> /dev/null ;;
        gh) command -v gh > /dev/null && gh_token ;;
    esac
}

#@incluir comun/repositorios-github/gh_token.sh
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
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] se comprobaria el token con GitHub y se guardaria en el Llavero"; return 0; }
    login=$(printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -q --proto =https -fsS --max-time 30 -K - \
        -H "Accept: application/vnd.github+json" -H "User-Agent: nexum-dev-stack" https://api.github.com/user 2> /dev/null \
        | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["login"])' 2> /dev/null)
    [ -n "$login" ] || { echo "GitHub no acepta ese token (¿caducado o sin permiso?)"; return 1; }
    if [ "$1" == --gh ]; then
        github_conf_set ORIGEN gh || return 1
    else
    # (al Llavero por la entrada de security: en la linea de ordenes se veria con ps)
    printf 'add-generic-password -U -a github -s %s -l "Nexum Dev Stack (GitHub)" -w %s\n' "$GITHUB_KEYRING_SERVICE" "$token" \
        | security -i > /dev/null 2>&1 || { echo "No se ha podido guardar el token en el Llavero"; return 1; }
        github_conf_set ORIGEN llavero || return 1
    fi
    [ -n "$(github_conf CUENTA)" ] || github_conf_set CUENTA "$login"
    echo "Conectado a GitHub como $login"
}

function github_disconnect() {
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] se quitaria el token de el Llavero"; return 0; }
    security delete-generic-password -s "$GITHUB_KEYRING_SERVICE" -a github > /dev/null 2>&1
    github_conf_set ORIGEN ""
    echo "Desconectado de GitHub (el token ya no está en el Llavero)"
}

#@incluir comun/repositorios-github/github_command.sh
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
    dir="$BASE_DIR/XAMPP-$version"
    if ! valid_version_name "$version" || [ ! -d "$dir" ] || [ -L "$dir" ]; then
        echo "No existe la version $version"

        return 1
    fi
    db_valid_name "$db" || return 1
    owner=$dir
    if db_names "$owner" | grep -qxF "$db"; then
        echo "Ya hay una BBDD $db en esa version: elige otro nombre"

        return 1
    fi
    if [ -n "$file" ] && { [ ! -f "$file" ] || [ -L "$file" ]; }; then
        echo "No existe el fichero $file"

        return 1
    fi
    if ! command -v git > /dev/null; then
        echo "Hace falta git para clonar el repositorio: xcode-select --install"

        return 1
    fi
    if [ ! -w "$HTDOCS_DIR" ]; then
        echo "No puedes escribir en $HTDOCS_DIR: el proyecto se clona con tu usuario, sin sudo"

        return 1
    fi

    task_plan "Montando el proyecto $folder" "Clonar el repositorio" "Cargarlo en XAMPP-$version" "Preparar la BBDD $db"
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
    echo "2/3 Cargando $folder en XAMPP-$version..."
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
    echo "Proyecto nuevo montado: $folder en XAMPP-$version con la BBDD $db"
}

# Carga un proyecto: activa la version (si se indica y no es la activa) y apunta el enlace del vhost
# a la carpeta del proyecto (lo mismo que rm web.local; ln -s <carpeta>/ web.local)
# Cargar un proyecto es todo o nada: la contraseña se pide antes de cambiar nada y, si se cancela (la
# ventana manda TERM a la tarea) o falla un paso, el enlace del vhost vuelve al proyecto de antes, la
# version activa a la de antes y Apache se recarga. Lo de antes, en LOAD_UNDO_*
LOAD_UNDO_LINK="" LOAD_UNDO_TARGET="" LOAD_UNDO_ACTIVE=""

function load_project_undo() {
    trap - TERM INT HUP
    [ -n "$LOAD_UNDO_LINK" ] || return 0
    local sudo="" now
    echo "Se deja como estaba: $LOAD_UNDO_LINK -> ${LOAD_UNDO_TARGET:-nada}"
    [ -w "$HTDOCS_DIR" ] || sudo=$SUDO
    now=$(readlink "$HTDOCS_DIR/$LOAD_UNDO_LINK" 2> /dev/null)
    if [ "$now" != "$LOAD_UNDO_TARGET" ]; then
        if [ -n "$LOAD_UNDO_TARGET" ]; then
            run $sudo ln -sfn "$LOAD_UNDO_TARGET" "$HTDOCS_DIR/$LOAD_UNDO_LINK"
        elif [ -L "$HTDOCS_DIR/$LOAD_UNDO_LINK" ]; then
            run $sudo rm "$HTDOCS_DIR/$LOAD_UNDO_LINK"
        fi
    fi
    if [ -n "$LOAD_UNDO_ACTIVE" ] && [ "$(active_name)" != "$LOAD_UNDO_ACTIVE" ]; then
        use_version "$LOAD_UNDO_ACTIVE"
    elif [ -f "$LINK/xamppfiles/logs/httpd.pid" ]; then
        run xampp_ctl reloadapache > /dev/null
    fi
    LOAD_UNDO_LINK=""
}

function load_project() {
    local folder=${1%/} version=$2 link rc

    valid_project "$folder" || return 1
    if [ -n "$version" ] && { ! valid_version_name "$version" || [ ! -d "$BASE_DIR/XAMPP-$version" ]; }; then
        echo "No existe la version $version"

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
    LOAD_UNDO_ACTIVE=$(active_name)
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
    for env in $(/usr/bin/python3 -I - "$root" <<'EOF'
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

    [ -w "$HTDOCS_DIR" ] || sudo=$SUDO
    if [ -L "$HTDOCS_DIR/$link" ]; then
        run $sudo rm "$HTDOCS_DIR/$link" || return 1
    fi
    run $sudo ln -s "$folder/" "$HTDOCS_DIR/$link" || return 1

    # Solo para este Mac: si cambia algo con la version en marcha, se reinicia para aplicarlo
    local web_dir=$(active_dir)
    [ -n "$version" ] && web_dir=$BASE_DIR/XAMPP-$version
    if [ -n "$web_dir" ]; then
        secure_version "$web_dir"
        case $? in
            0) secured=0 ;;
            2) secure_failed 2 "$web_dir" && return 1 ;;
        esac
        vhosts_root && secured=0
    fi

    if [ -n "$version" ] && [ "$(active_dir)" != "$(realpath_f "$BASE_DIR/XAMPP-$version")" ]; then
        echo "Activando XAMPP-$version..."
        use_version "$version" || return 1
    elif [ -n "$(active_dir)" ] && ! lampp_running; then
        echo "Arrancando $(basename "$(active_dir)")..."
        run xampp_ctl start
    elif [ $secured -eq 0 ]; then
        echo "Reiniciando $(basename "$(active_dir)") para que solo se pueda entrar desde este Mac..."
        run xampp_ctl restart > /dev/null || { echo "No se ha podido reiniciar. Reinicia la version activa."; return 1; }
    elif [ -f "$LINK/xamppfiles/logs/httpd.pid" ]; then
        # Cada proceso de PHP-FPM recuerda a donde apuntaba el enlace (realpath_cache, 120 s) y
        # seguiria sirviendo el proyecto anterior: recarga suave de PHP-FPM y Apache
        echo "Recargando Apache para que PHP no siga sirviendo el proyecto anterior..."
        run xampp_ctl reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
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

    echo "Proyecto cargado: $link -> $folder$([ -n "$(active_dir)" ] && echo " ($(basename "$(active_dir)"))")"
}

