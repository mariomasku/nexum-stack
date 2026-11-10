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
    local pinned
    while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        name=$(version_name "$dir")
        [ -f "$dir/xamppfiles/etc/pvm-stack" ] || continue
        cur=$(stack_fields "$dir")
        # (las de ahora, XAMPP-X.Y.Z, llevan su parche en el nombre: no se rehacen, se instala la nueva al
        # lado y se le pasan las BBDD con pasar-version)
        pinned=0
        [[ "$name" =~ ^[0-9]+\.[0-9]+$ ]] || pinned=1
        [ -z "$releases" ] && continue
        full=$(rebuild_version "$dir" "$releases")
        [ -z "$full" ] && { echo "E|la última versión de la rama de XAMPP-$name"; continue; }
        new=$(stack_versions "$full")
        IFS='|' read -r -a a <<< "$cur"
        IFS='|' read -r -a b <<< "$new"
        for i in 0 1 2 3 4 5; do
            # (lo que no se ha podido consultar sale como su rama seguida de .x: no cuenta)
            [ -z "${b[$i]}" ] || [[ "${b[$i]}" == *.x ]] && continue
            if [ "${a[$i]}" != "${b[$i]}" ] && [ "$(printf '%s\n%s\n' "${a[$i]}" "${b[$i]}" | sort -V | tail -1)" == "${b[$i]}" ]; then
                if [ $pinned -eq 1 ]; then
                    echo "F|$name|${names[$i]} ${a[$i]:-?} → ${b[$i]}: instala la nueva a su lado (Instalar versión) y pásale las BBDD"
                else
                    echo "L|$name|${names[$i]}|${a[$i]:-?}|${b[$i]}"
                fi
                n=$((n + 1))
            fi
        done
    done < <(version_dirs)
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
            img=php:$v-apache
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
            L) echo "  XAMPP-${f[1]}: ${f[2]} ${f[3]} → ${f[4]}"
               [[ " $folders " == *" ${f[1]} "* ]] || folders+=" ${f[1]}" ;;
            K) echo "  ${f[1]} (${f[2]}): versión nueva en Docker Hub"; imgs+=" ${f[1]}" ;;
            X) echo "  ${f[1]}: ${f[2]} → ${f[3]}"; progs+=" ${f[1]}" ;;
            F) echo "  XAMPP-${f[1]}: ${f[2]}" ;;
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
    for v in $folders; do steps+=("XAMPP-$v"); done
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
                v=${v#php:}; v=${v%-apache}
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
        echo "XAMPP-$v: se rehace con lo último de su rama (sigue funcionando mientras se compila)"
        ( cli_rebuild "$v" ) || fail=1
    done
    [ $fail -eq 0 ] && echo "Todo al día." || echo "Algo no se ha podido actualizar: mira lo de arriba."
    return $fail
}

#@incluir comun/componentes/copies_migrate.sh
#@incluir comun/componentes/clean_size_text.sh

# El manual (manual_command): con Linux o Mac ya elegido, y como se abre un fichero en este sistema
MANUAL_SO=mac
function manual_open() {
    /usr/bin/open "$1"
}
#@incluir comun/componentes/manual_command.sh
# Limpieza en el Mac: las versiones son las de BASE_DIR, con sus logs, var/mysql y temp en xamppfiles; la carpeta
# temporal, /private/tmp (/tmp es un enlace a ella) y la tuya (TMPDIR, en /var/folders)
CLEAN_STACK_SUB="xamppfiles/"
CLEAN_TMP_DIRS=(/private/tmp)
if [ -n "$TEST_DIR" ]; then
    CLEAN_TMP_DIRS=("$TEST_DIR/tmp")
elif [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && [ ! -L "${TMPDIR%/}" ] && [ -O "$TMPDIR" ]; then
    [ "$(cd "$TMPDIR" && pwd -P)" == "/private/tmp" ] || CLEAN_TMP_DIRS+=("${TMPDIR%/}")
fi

function clean_version_dirs() {
    version_dirs
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

# Copias de bases, configuraciones de proyectos y registros: solo para tu usuario (en el Mac la
# carpeta personal suele ser 755: cualquier otro usuario del Mac podria leerlas)
for dir in "$COPIES_DIR" "$LOG_DIR"; do
    if [ -d "$dir" ] && [ -O "$dir" ] && [ ! -L "$dir" ]; then
        chmod 700 "$dir" 2> /dev/null
        find "$dir" -maxdepth 2 -type f -user "$(id -u)" -perm +077 -exec chmod go-rwx {} + 2> /dev/null
    fi
done


