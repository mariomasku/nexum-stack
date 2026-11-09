# ===========================================================================
# phpMyAdmin: actualizar el de una version
# ===========================================================================
# phpMyAdmin que admite cada PHP: la 5.2 (la ultima) desde PHP 7.2.5, la 5.1.4 desde la 7.1.3 y la
# 4.9.11 antes. Los XAMPP traen la 4.9.2, 5.2.0 o 5.2.1, con fallos de seguridad corregidos despues.
function pma_for_php() {
    local php=$1
    if [ "$(printf '%s\n%s\n' 7.2.5 "$php" | vsort | head -1)" == 7.2.5 ]; then
        latest_pma
    elif [ "$(printf '%s\n%s\n' 7.1.3 "$php" | vsort | head -1)" == 7.1.3 ]; then
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
        for d in $(version_dirs); do
            [ -f "$d/xamppfiles/phpmyadmin/config.inc.php" ] || continue
            update_pma "$(version_name "$d")" || rc=1
        done
        return $rc
    fi
    valid_version_name "$version" && [ -d "$BASE_DIR/XAMPP-$version" ] \
        || { echo "No existe la version $version"; return 1; }
    root="$BASE_DIR/XAMPP-$version/xamppfiles"
    dir=$root/phpmyadmin
    if [ ! -f "$dir/config.inc.php" ]; then
        echo "$version no tiene phpMyAdmin con su configuracion ($dir/config.inc.php)"
        return 1
    fi
    php=$(php_version "$BASE_DIR/XAMPP-$version")
    cur=$(pma_installed "$dir")
    want=$(pma_for_php "$php")
    [[ "$want" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "No se ha podido saber que phpMyAdmin poner"; return 1; }
    if [ -n "$cur" ] && [ "$(printf '%s\n%s\n' "$want" "$cur" | vsort | tail -1)" == "$cur" ]; then
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
    if [ -n "$SUDO" ] && { [ -L "$dir" ] || ! trusted_version_dir "$BASE_DIR/XAMPP-$version"; }; then
        echo "No se cambia phpMyAdmin: XAMPP-$version no es de root (lvm-instalador asegurar --todas)"
        return 1
    fi
    task_step
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-pma.XXXXXX") || return 1
    sum=$(pma_sum "$want")
    if ! download "https://files.phpmyadmin.net/phpMyAdmin/$want/phpMyAdmin-$want-all-languages.tar.xz" "$tmp/pma.tar.xz" "$sum" \
            "https://files.phpmyadmin.net/phpMyAdmin/$want/phpMyAdmin-$want-all-languages.tar.xz.asc" PMA \
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
    grp=$(stat -f %Sg "$dir/tmp" 2> /dev/null || echo root)
    # phpMyAdmin no trae enlaces: uno en la carpeta (que es tuya hasta que root la copia) seria de
    # otro programa. Se mira otra vez en la copia, ya de root, y tmp la crea root vacia (si fuera un
    # enlace, root cambiaria el dueño y los permisos de lo que apunta)
    if [ -n "$(find "$new" \( -type l -o -type f -links +1 \) -print -quit)" ]; then
        rm -rf "$tmp"
        echo "El phpMyAdmin descargado tiene enlaces (no deberia): no se cambia nada"
        return 1
    fi
    task_step
    if ! { $SUDO rm -rf "$root/phpmyadmin.anterior" && $SUDO mv "$dir" "$root/phpmyadmin.anterior"; }; then
        echo "No se ha podido apartar $dir: no se cambia nada"
        rm -rf "$tmp"
        return 1
    fi
    if ! { $SUDO cp -R "$new" "$dir" \
            && [ -z "$($SUDO find "$dir" -type l -print -quit)" ] \
            && $SUDO chown -R root:admin "$dir" \
            && $SUDO chmod -R go-w "$dir" \
            && $SUDO rm -rf "$dir/tmp" \
            && $SUDO install -d -o 0 -g "$grp" -m 775 "$dir/tmp"; }; then
        $SUDO rm -rf "$dir" && $SUDO mv "$root/phpmyadmin.anterior" "$dir"
        echo "No se ha podido cambiar $dir: se ha dejado el phpMyAdmin anterior"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    if [ "$(active_dir)" == "$(realpath_f "$BASE_DIR/XAMPP-$version")" ] && service_running apache; then
        run xampp_ctl reloadapache > /dev/null
    fi
    echo "phpMyAdmin $want instalado en $version"
}

# Versiones de antes de la 1.39.3 que siguen en /Applications: el gestor ya no las arranca como root.
# Se avisa (en Terminal; la ventana lo dice en sus avisos) y el panel ofrece pasarlas
if [ -z "$TEST_DIR" ] && [ "$DRY" -eq 0 ] && [[ "$1" != gui-* ]] && [ "$1" != migrar ] && [ "$1" != instalar-gestor ] \
        && [ "$1" != construir-pila ] && [ -t 1 ] && [ -n "$(legacy_dirs)" ]; then
    echo "Aviso: hay versiones en $LEGACY_DIR de antes de la 1.39.3, que el gestor ya no arranca como administrador." >&2
    echo "Pasalas a $BASE_DIR (de root) con: lvm-instalador migrar" >&2
    if [ -z "$1" ] && ui_yesno "Las versiones de antes de la 1.39.3 estan en $LEGACY_DIR, donde puede escribir el grupo admin (tu usuario), y ya no se arrancan como administrador.\n\nSe pasan a $BASE_DIR (de root) con sus BBDD, proyectos, vhosts y certificados; en $LEGACY_DIR queda un enlace a cada una. Pide tu contraseña de administrador.\n\n¿Pasarlas ahora?"; then
        gestor_migrate
    fi
fi

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
        gui-*|node-*|exportar-bd|descargar-bd|docker-registros|construir-pila|version|--version|-v|acerca|about|novedades|procesos) ;;
        *) sudo_first || exit 130 ;;
    esac
fi

case "$1" in
    "")
        # Abierto desde una aplicacion de la 1.1.0 o anterior (abria el panel en Terminal): se pone
        # al dia y, si ya tiene ventana, se abre la ventana en lugar del panel
        [ "$LVM_ACCESO" == "1" ] && migrate_old_app
        if [ "$LVM_ACCESO" == "1" ] && [ "$DRY" -eq 0 ] && [ -d "$APP_BUNDLE" ]; then
            update_app
            if [ -x "$APP_BUNDLE/Contents/MacOS/lvm-app" ]; then
                open "$APP_BUNDLE"
                exit 0
            fi
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
    use|usar) use_version "$2" ;;
    list) list_versions ;;
    list-db) list_databases ;;
    status|estado) echo -e "$(status_text)" ;;
    disable|desactivar) disable_version ;;
    remove|desinstalar) cli_remove "$2" "$3" ;;
    ventana|gui) open_window ;;
    apartar) set_aside_official ;;
    volver-oficial) restore_official "$2" ;;
    importar-copias) import_backups "$2" ;;
    arrancar|start) control_lampp start ;;
    parar|stop) control_lampp stop ;;
    reiniciar|restart) control_lampp restart ;;
    importar-bd) import_database "$2" "$3" "${@:4}" ;;
    crear-bd) create_database "$2" ;;
    borrar-bd) drop_database "$2" "$3" ;;
    gui-datos) gui_data ;;
    gui-vuelta) gui_round ;;
    gui-ramas) gui_branches ;;
    gui-parches) gui_patches "$2" ;;
    gui-fechas) gui_php_dates ;;
    gui-al-dia) gui_up_to_date "$2" ;;
    gui-bd-comprobar) gui_db_check ;;
    gui-bd-info) gui_db_info "$2" ;;
    gui-bbdd-tamanos) gui_db_sizes ;;
    gui-proyectos-tamanos) gui_project_sizes "$2" ;;
    gui-proyectos) gui_projects ;;
    gui-docker) gui_docker ;;
    gui-docker-estadisticas) gui_docker_stats ;;
    docker-instalar) docker_install ;;
    tunel) tunnel_status ;;
    tunel-instalar) tunnel_install ;;
    tunel-abrir) shift; tunnel_open "$@" ;;
    tunel-cerrar) tunnel_close ;;
    node-arrancar) shift; node_start "$@" ;;
    node-parar) node_stop "$2" ;;
    node-registro) node_log "$2" ;;
    gui-node) gui_node ;;
    docker-crear) shift; docker_create "$@" ;;
    docker-nuevo) shift; docker_web_create "$@" ;;
    docker-php-anadir) docker_web_add "$2" "$3" ;;
    docker-php-añadir) docker_web_add "$2" "$3" ;;
    docker-php-quitar) docker_web_remove "$2" "$3" ;;
    docker-php-elegir) docker_web_switch "$2" "$3" ;;
    docker-pasar) docker_pass "$2" ;;
    docker-parar-todo) docker_stop_all ;;
    docker-web) shift; docker_web_command "$@" ;;
    docker-arrancar|docker-parar|docker-registros|docker-borrar) docker_action "${1#docker-}" "$2" ;;
    docker-php) docker_set_php "$2" "$3" ;;
    docker-contenedor) docker_container_action "$2" "$3" ;;
    docker-imagenes) docker_image_action "$2" "$3" ;;
    docker-volumen-borrar) docker_volume_remove "$2" ;;
    docker-migrar) docker_migrate_command "$2" ;;
    docker-imagen) docker_update_image "$2" ;;
    docker-clave) docker_db_password "$2" ;;
    docker-usuario-pruebas) docker_test_admin "$2" ;;
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
    gui-paquete) gui_package ;;
    actualizar-gestor) install_update "$2" ;;
    migrar) gestor_migrate "$2" ;;
    instalar-gestor) gestor_migrate --ventana ;;
    # (desde la 1.39.5 no hace nada: las firmas las comprueba el gestor, sin gnupg)
    preparar-firma) echo "Ya no hace falta gnupg: las firmas las comprueba el propio gestor con el Python del sistema" ;;
    servicio) service_control "$2" "$3" ;;
    asegurar) secure_command "$2" ;;
    reparar-bd-sistema) repair_db_system ;;
    arreglar-certificados) fix_certs ;;
    confiar-certificados) browser_trust "$2" ;;
    actualizar-phpmyadmin) update_pma "$2" ;;
    hosts-falsear) hosts_fake_one "$2" "$3" ;;
    media-produccion) media_proxy "$2" "$3" ;;
    media-proyecto) media_project "$2" "$3" ;;
    gui-wp-produccion) gui_wp_prod "$2" ;;
    ps-imagenes) ps_images "$2" "$3" ;;
    hosts-enlace) hosts_fix_link ;;
    nuevo-dominio) new_custom_domain "$2" "$3" "$4" ;;
    cerrar-procesos) close_processes "$2" ;;
    procesos) lampp_processes --sudo | awk -F'|' '{ printf "%-8s %-8s %-12s %-12s %s\n", $2, $3, $4, ($5 == "?" ? "anterior" : $5), $7 ($6 == 1 ? "  <- sobra" : "") }' ;;
    vhosts|editar-vhosts) edit_vhosts "$2" ;;
    hosts|editar-hosts) edit_hosts "$2" "$3" ;;
    exportar-bd|descargar-bd) export_database "$2" "$3" "$4" ;;
    copiar-bd) shift; copy_database "$@" ;;
    pasar-version) move_to_version "$2" "$3" ;;
    barrera-web) web_barrier_command "$2" ;;
    correo) mail_command "$2" "$3" ;;
    vincular-bd) link_database "$2" "$3" "$4" ;;
    rehacer|actualizar) cli_rebuild "$2" ;;
    github) shift; github_command "$@" ;;
    github-conectar) github_connect "$2" ;;
    github-desconectar) github_disconnect ;;
    repos) shift; repos_list "$@" ;;
    repo-traer) repo_fetch "$2" "$3" ;;
    docker-reposo) shift; docker_idle_command "$@" ;;
    docker-bd) docker_db_mode "$2" "$3" "$4" ;;
    componentes) components_check "$2" ;;
    componentes-actualizar) components_update ;;
    descargas) downloads_command "$2" ;;
    version|--version|-v) echo "$APP_NAME $APP_VERSION" ;;
    acerca|about) echo -e "$(about_text)" ;;
    novedades) changes_text ;;
    -h|--help|--ayuda) sed -n '3,/^$/p' "$SELF" | sed 's/^# \{0,1\}//' ;;
    *) echo "Accion desconocida: $1 (usa --ayuda)"; exit 1 ;;
esac
