# ===========================================================================
# Componentes: los parches nuevos de todo lo que usa el gestor
# ===========================================================================
# Lo que tiene un parche nuevo publicado: cada version de PHP (su PHP, Apache, MariaDB, ProFTPD, Perl y
# phpMyAdmin, frente a lo ultimo de su rama), las imagenes de Docker que se usan (las MariaDB comunes,
# phpMyAdmin y la base de cada imagen de PHP, frente a su huella en Docker Hub: sin descargar nada), y
# Mailpit y cloudflared (frente a los que pone esta version del gestor). componentes [--sin-docker]:
#   L|carpeta|componente|instalada|nueva   una version de PHP: se rehace entera con lo ultimo de su rama
#   F|carpeta|motivo                       una version que no se pone al dia sola (parche concreto, XAMPP)
#   K|imagen|para que                      una imagen de Docker con una version nueva en Docker Hub
#   X|programa|instalada|nueva             Mailpit o cloudflared
#   E|lo que no se ha podido consultar
#   S|cuantos componentes tienen parche nuevo
function components_check() {
    local dir name full cur new i n=0 names=(PHP Apache MariaDB ProFTPD Perl phpMyAdmin) releases img v
    local a b
    releases=$(php_releases)
    [ -z "$releases" ] && echo "E|php.net (las versiones de PHP)"
    for dir in $(lampp_dirs); do
        name=${dir#/opt/lampp-}
        is_fpm_install "$dir" || { echo "F|$name|XAMPP oficial: no se rehace (instala una versión de PHP nueva al lado)"; continue; }
        cur=$(stack_fields "$dir")
        [ "$name" != "$(cut -d'|' -f1 <<< "$cur" | sed 's/\.[0-9]*$//')" ] && { echo "F|$name|parche concreto de PHP: se queda en el suyo"; continue; }
        [ -z "$releases" ] && continue
        full=$(rebuild_version "$dir" "$releases")
        [ -z "$full" ] && { echo "E|la última versión de la rama de lampp-$name"; continue; }
        new=$(stack_versions "$full")
        IFS='|' read -r -a a <<< "$cur"
        IFS='|' read -r -a b <<< "$new"
        for i in 0 1 2 3 4 5; do
            # (lo que no se ha podido consultar sale como su rama seguida de .x: no cuenta)
            [ -z "${b[$i]}" ] || [[ "${b[$i]}" == *.x ]] && continue
            if [ "${a[$i]}" != "${b[$i]}" ] && [ "$(printf '%s\n%s\n' "${a[$i]}" "${b[$i]}" | sort -V | tail -1)" == "${b[$i]}" ]; then
                echo "L|$name|${names[$i]}|${a[$i]:-?}|${b[$i]}"
                n=$((n + 1))
            fi
        done
    done
    if [ "$1" != --sin-docker ] && docker_ready > /dev/null 2>&1; then
        for v in $(docker_maria_versions); do
            img=mariadb:$v
            docker_image_outdated "$img" && { echo "K|$img|la MariaDB $v común de Docker"; n=$((n + 1)); }
        done
        if dk image inspect "$DOCKER_PMA_IMAGE" > /dev/null 2>&1 && docker_image_outdated "$DOCKER_PMA_IMAGE"; then
            echo "K|$DOCKER_PMA_IMAGE|phpMyAdmin de Docker"
            n=$((n + 1))
        fi
        for v in $DOCKER_PHP_VERSIONS; do
            dk image inspect "nexum-php:$v" > /dev/null 2>&1 || continue
            img=php:$v-fpm
            docker_image_outdated "$img" && { echo "K|$img|la imagen de PHP $v de Docker (nexum-php:$v)"; n=$((n + 1)); }
        done
    fi
    if mailpit_installed && [ "$(mailpit_installed_version)" != "$MAILPIT_VERSION" ]; then
        echo "X|Mailpit|$(mailpit_installed_version)|$MAILPIT_VERSION"
        n=$((n + 1))
    fi
    if tunnel_installed && [ "$(tunnel_installed_version)" != "$TUNNEL_VERSION" ]; then
        echo "X|cloudflared|$(tunnel_installed_version)|$TUNNEL_VERSION"
        n=$((n + 1))
    fi
    echo "S|$n"
}

#@incluir comun/componentes/docker_image_outdated.sh
# componentes-actualizar: pone al dia todo lo que diga components_check. Las versiones de PHP se rehacen
# (la de ahora sigue funcionando mientras se compila); las MariaDB comunes, phpMyAdmin y las imagenes de
# PHP se descargan de nuevo y sus contenedores en marcha se rehacen (unos segundos sin servicio: su BBDD
# y su configuracion no cambian); Mailpit y cloudflared se instalan con su version. --copia: a cada
# version que se rehace (como actualizar --copia)
function components_update() {
    local out line f cf folders="" imgs="" progs="" fail=0 v slug dir running
    [ "$1" == "--copia" ] && STACK_DB_COPY=1
    echo "Buscando parches nuevos..."
    out=$(components_check)
    while IFS= read -r line; do
        IFS='|' read -r -a f <<< "$line"
        case ${f[0]} in
            L) echo "  lampp-${f[1]}: ${f[2]} ${f[3]} → ${f[4]}"
               [[ " $folders " == *" ${f[1]} "* ]] || folders+=" ${f[1]}" ;;
            K) echo "  ${f[1]} (${f[2]}): versión nueva en Docker Hub"; imgs+=" ${f[1]}" ;;
            X) echo "  ${f[1]}: ${f[2]} → ${f[3]}"; progs+=" ${f[1]}" ;;
            E) echo "  (no se ha podido consultar: ${f[1]})" ;;
        esac
    done <<< "$out"
    if [ -z "$folders$imgs$progs" ]; then
        echo "Todo está al día: no hay parches nuevos."
        return 0
    fi
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] se actualizaria lo de arriba"; return 0; }
    local steps=()
    for v in $imgs; do
        case $v in
            mariadb:*) steps+=("MariaDB ${v#mariadb:} de Docker") ;;
            "$DOCKER_PMA_IMAGE") steps+=("phpMyAdmin de Docker") ;;
            php:*) v=${v#php:}; steps+=("Imagen de PHP ${v%-*}") ;;
            *) steps+=("$v") ;;
        esac
    done
    for v in $progs; do steps+=("$v"); done
    for v in $folders; do steps+=("lampp-$v"); done
    task_plan "Actualizando los componentes" "${steps[@]}"
    for v in $imgs; do
        task_step
        case $v in
            mariadb:*)
                v=${v#mariadb:}
                echo "MariaDB $v común de Docker: la imagen nueva y su contenedor de nuevo (sus BBDD no cambian)"
                # (y, de paso, que se ponga al dia sola al cambiar de parche: MARIADB_AUTO_UPGRADE)
                cf=$DOCKER_DIR/mariadb-$v/compose.yaml
                if dk pull "mariadb:$v" && awk '/^      MARIADB_AUTO_UPGRADE:/ { next } { print } /^      MARIADB_ROOT_PASSWORD: / { print "      MARIADB_AUTO_UPGRADE: \"1\"" }' "$cf" > "$cf.nuevo" \
                        && chmod 600 "$cf.nuevo" && mv -f "$cf.nuevo" "$cf"; then
                    [ -n "$(dk ps -q --filter "name=^$(docker_maria_name "$v")\$" 2> /dev/null)" ] && { docker_maria_up "$v" > /dev/null || fail=1; }
                else
                    fail=1
                fi ;;
            "$DOCKER_PMA_IMAGE")
                echo "phpMyAdmin de Docker: la imagen nueva"
                dk pull "$DOCKER_PMA_IMAGE" || { fail=1; continue; }
                [ "$(docker_web_state)" == marcha ] && { docker_web_up > /dev/null || fail=1; } ;;
            php:*)
                v=${v#php:}; v=${v%-fpm}
                echo "Imagen de PHP $v de Docker: de nuevo, con lo último de Docker Hub"
                docker_php_image "$v" --nueva || { echo "No se ha podido rehacer la imagen de PHP $v: sigue con la anterior"; fail=1; continue; }
                for slug in $(docker_projects); do
                    [[ " $(docker_conf "$slug" PHP) " == *" $v "* ]] || continue
                    dir=$DOCKER_DIR/$slug
                    running=$(dk ps --filter "label=com.docker.compose.project=nexum-$slug" --format '{{.Label "com.docker.compose.service"}}' 2> /dev/null)
                    [ -n "$running" ] && { dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d $running > /dev/null || fail=1; }
                done ;;
        esac
    done
    [ -n "$imgs" ] && dk image prune -f > /dev/null 2>&1
    [[ " $progs " == *" Mailpit "* ]] && { task_step; mailpit_install || fail=1; }
    [[ " $progs " == *" cloudflared "* ]] && { task_step; tunnel_install || fail=1; }
    for v in $folders; do
        task_step
        echo "lampp-$v: se rehace con lo último de su rama (sigue funcionando mientras se compila)"
        ( cli_rebuild "$v" ) || fail=1
    done
    [ $fail -eq 0 ] && echo "Todo al día." || echo "Algo no se ha podido actualizar: mira lo de arriba."
    return $fail
}

# actualizar-a <version> <php>: pasa una version a otro parche de PHP de su rama. Para las que no se
# actualizan en su carpeta: una lampp-X.Y.Z (se queda en su parche) o un XAMPP (sus binarios no se
# pueden arreglar). Instala PHP <php> con su pila propia en lampp-<php>, al lado (la de antes no se
# toca), le copia todas las BBDD de la de antes con sus vinculos a las carpetas de los proyectos
# (como copiar-bd: la de antes sigue igual) y, si la de antes era la activa, activa la nueva. La de
# antes se queda hasta que la desinstales. Si <php> es el mismo parche de una pila propia sin el
# parche de seguridad (7.4.33, 8.0.30, 8.1.34), se vuelve a compilar en su carpeta con el
function upgrade_to() {
    local from=$1 php=$2 to=$2 src dst old db link failed=() n=0 owner have
    # (--copia: para cuando se vuelve a compilar en su carpeta, como actualizar --copia)
    [ "$3" == "--copia" ] && STACK_DB_COPY=1
    if [ -z "$from" ] || ! [[ "$php" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Uso: lvm-instalador actualizar-a <version instalada> <version de PHP, como 8.3.36>"
        return 1
    fi
    valid_version_name "$from" || { echo "Version no valida"; return 1; }
    src=${TEST_DIR:-/opt}/lampp-$from dst=${TEST_DIR:-/opt}/lampp-$php
    [ -d "$src" ] && [ ! -L "$src" ] || { echo "No existe la version lampp-$from"; return 1; }
    old=$(stack_fields "$src" | cut -d'|' -f1)
    if [ "${old%.*}" != "${php%.*}" ]; then
        echo "lampp-$from es PHP $old: solo se pasa a otro parche de su rama (${old%.*}.x)"
        return 1
    fi
    if [ "$(printf '%s\n' "$old" "$php" | sort -V | tail -1)" != "$php" ]; then
        echo "PHP $php es anterior a PHP $old: no se actualiza hacia atras"
        return 1
    fi
    if [ "$src" == "$dst" ]; then
        if ! is_stack_install "$src" || ! php2shell_backport "$php" > /dev/null || [ -f "$src/$PHP2SHELL_MARK" ]; then
            echo "lampp-$from ya es PHP $php: no hay nada que actualizar"
            return 0
        fi
        echo "lampp-$from se vuelve a compilar con el parche de seguridad de PHP2Shell (conserva sus BBDD"
        echo "si su MariaDB sigue en la misma rama; si no, empieza con BBDD vacias$([ "${STACK_DB_COPY:-0}" -eq 1 ] && echo ", con una copia antes en ~/nexum-backups"))"
        UI=text
        install_plan "reparar:$php"
        return
    fi
    # (si PHP <php> ya esta en otra carpeta, como lampp-8.2 con la 8.2.35, las BBDD van ahi)
    have=$(php_installed_in "$php")
    if [ -n "$have" ] && [ "$have" != "$src" ] && [ -z "$TEST_DIR" ]; then
        dst=$have to=${have#/opt/lampp-}
    fi
    if [ -e "$dst" ]; then
        if ! is_fpm_install "$dst" || [ "$(php_version "$dst")" != "$php" ]; then
            echo "Ya existe $dst y no es PHP $php: no se cambia nada"
            return 1
        fi
        echo "lampp-$to ya esta instalada: solo se le copian las BBDD de lampp-$from"
    else
        echo "Se instala PHP $php en lampp-$to, al lado de lampp-$from (que no se toca)"
        UI=text
        install_plan "php:$php" || return 1
        [ "$DRY" -eq 1 ] && { echo "  [simulacion] copia de las BBDD de lampp-$from a lampp-$to y sus vinculos"; return 0; }
    fi
    owner=$(data_owner "$src")
    if [ -n "$owner" ] && [ "$owner" != "$from" ]; then
        echo "lampp-$from usa las BBDD de lampp-$owner: no se copia ninguna (copialas con copiar-bd si las quieres)"
    else
        for db in $(db_names "$src"); do
            n=$((n + 1))
            echo ""
            echo "== BBDD $db =="
            link=$(linked_folder "$db" "$from")
            # (cada copia en un subproceso: copiar-bd usa trap y exit)
            if ! ( copy_database "$db" "$from" "$to" ${link:+--carpeta "$link"} ); then
                failed+=("$db")
            fi
        done
    fi
    echo ""
    if [ "$(active_dir)" == "$src" ]; then
        echo "lampp-$from era la activa: se activa lampp-$to"
        ( use_lampp "$to" ) || echo "No se ha podido activar lampp-$to: activala en Versiones de PHP"
    fi
    echo "Copiadas $((n - ${#failed[@]})) de $n BBDD de lampp-$from a lampp-$to."
    [ ${#failed[@]} -gt 0 ] && echo "No se han podido copiar: ${failed[*]} (copialas con copiar-bd)"
    echo "lampp-$from se queda como estaba: cuando compruebes que todo va bien con lampp-$to,"
    echo "desinstalala (Versiones de PHP, menu ⋮ de la version, Desinstalar)."
    [ ${#failed[@]} -eq 0 ]
}

#@incluir comun/componentes/copies_migrate.sh
#@incluir comun/componentes/clean_size_text.sh

# El manual (manual_command): con Linux o Mac ya elegido, y como se abre un fichero en este sistema
MANUAL_SO=linux
function manual_open() {
    xdg-open "$1" > /dev/null 2>&1 &
}
#@incluir comun/componentes/manual_command.sh
# Limpieza en Linux: las versiones son /opt/lampp-* (en las pruebas, las de LVM_PRUEBA), con sus logs, var/mysql
# y temp sin subcarpeta; la carpeta temporal, /tmp y la tuya (TMPDIR) si es otra
CLEAN_STACK_SUB=""
CLEAN_TMP_DIRS=(/tmp)
if [ -n "$TEST_DIR" ]; then
    CLEAN_TMP_DIRS=("$TEST_DIR/tmp")
elif [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && [ ! -L "${TMPDIR%/}" ] && [ -O "$TMPDIR" ]; then
    [ "$(cd "$TMPDIR" && pwd -P)" == "/tmp" ] || CLEAN_TMP_DIRS+=("${TMPDIR%/}")
fi

function clean_version_dirs() {
    if [ -n "$TEST_DIR" ]; then
        find "$TEST_DIR" -maxdepth 1 -type d -name "lampp-*" 2> /dev/null | sort -V
    else
        lampp_dirs
    fi
}

if [ "$1" == "--simular" ]; then
    DRY=1
    shift
fi

# (no en --simular, ni en las pruebas, LVM_PRUEBA, ni al pedir solo la version o las novedades, como
# hace el empaquetador: tu carpeta se queda como esta)
case "${1:-}" in
    version|--version|-v|acerca|about|novedades|-h|--help|--ayuda|construir-pila) ;;
    *) [ "$DRY" -eq 0 ] && [ -z "$TEST_DIR" ] && copies_migrate ;;
esac

for cmd in curl python3; do
    command -v $cmd > /dev/null || { echo "Falta el comando $cmd. Instalalo con: sudo apt install $cmd"; exit 1; }
done

# Copias de bases, configuraciones de proyectos y registros: solo para tu usuario
for dir in "$COPIES_DIR" "$LOG_DIR"; do
    if [ -d "$dir" ] && [ -O "$dir" ] && [ ! -L "$dir" ]; then
        chmod 700 "$dir" 2> /dev/null
        find "$dir" -maxdepth 2 -type f -user "$(id -u)" -perm /077 -exec chmod go-rwx {} + 2> /dev/null
    fi
done


