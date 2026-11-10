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

#@incluir comun/phpmyadmin/pma_sum.sh
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
        echo "No se cambia phpMyAdmin: /opt o $root no son del administrador (nexum asegurar --todas)"
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

#@incluir comun/phpmyadmin/node_lines.sh
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
        gui-*|node-*|exportar-bd|descargar-bd|docker-registros|construir-pila|version|--version|-v|acerca|about|novedades|procesos|limpieza|copias-ficheros|manual) ;;
        # (copias: solo vaciar, y solo si hay copias de root que tu usuario no puede borrar)
        copias) [ "$2" == vaciar ] && copies_need_root && { sudo_first || exit 130; } ;;
        # (limpiar y limpiar-proyecto: solo si algo de lo que se va a limpiar es de root)
        limpiar) clean_need_root "${@:2}" && { sudo_first || exit 130; } ;;
        limpiar-proyecto) clean_project_need_root "${@:2}" && { sudo_first || exit 130; } ;;
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
    docker-pasar) docker_pass "$2" "$3" ;;
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
        # shellcheck disable=SC1090  # (el fichero lo pasa quien llama)
        . "$2"
        cd "$build" || exit 1
        function stack_fail() { stack_child_fail; }
        STEP_LOG="" STEP_DESC=""
        stack_build_phase
        ;;
    barrera-web|barrera-webs) cross_site_command "$2" ;;
    correo) mail_command "$2" "$3" ;;
    reparar-bd-sistema) repair_db_system "$2" ;;
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
    rehacer|actualizar) cli_rebuild "$2" "$3" ;;
    github) shift; github_command "$@" ;;
    github-conectar) github_connect "$2" ;;
    github-desconectar) github_disconnect ;;
    repos) shift; repos_list "$@" ;;
    repo-traer) repo_fetch "$2" "$3" ;;
    docker-bd) docker_db_mode "$2" "$3" "$4" ;;
    docker-reposo) shift; docker_idle_command "$@" ;;
    componentes) components_check "$2" ;;
    componentes-actualizar) components_update "$2" ;;
    actualizar-a) upgrade_to "$2" "$3" "$4" ;;
    descargas) downloads_command "$2" ;;
    add-xampp) ( install_xampp "$2" ) ;;
    version|--version|-v) echo "$APP_NAME $APP_VERSION" ;;
    acerca|about) echo -e "$(about_text)" ;;
    novedades) changes_text ;;
    copias) copies_command "$2" ;;
    copias-ficheros) copies_files_command "$2" ;;
    limpieza) clean_list ;;
    gui-limpieza) clean_measure "${CLEAN_KEYS[@]}" | cut -d'|' -f1-4 ;;
    limpiar) shift; clean_command "$@" ;;
    gui-limpiar-proyecto) gui_clean_project "$2" ;;
    limpiar-proyecto) shift; clean_project_command "$@" ;;
    manual) shift; manual_command "$@" ;;
    -h|--help|--ayuda) sed -n '3,/^$/p' "$SELF" | sed 's/^# \{0,1\}//' ;;
    *) echo "Accion desconocida: $1 (usa --ayuda)"; exit 1 ;;
esac
#@manual linux
