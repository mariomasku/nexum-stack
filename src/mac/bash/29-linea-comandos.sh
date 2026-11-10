# ===========================================================================
# Linea de comandos
# ===========================================================================

function cli_install() {
    local php="" yes=0 selected="" full branch

    while [ -n "$1" ]; do
        case "$1" in
            --php) php=${2//,/ }; shift 2 ;;
            --si|--yes|-y) yes=1; shift ;;
            *) echo "Opcion desconocida: $1"; return 1 ;;
        esac
    done

    [ -z "$php" ] && echo "Indica las ramas de PHP (o un parche concreto), por ejemplo: lvm-instalador instalar --php 7.4,8.4,8.3.10" && return 1

    local releases=$(php_releases) all=""
    for branch in $php; do
        if [[ "$branch" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # Un parche concreto (8.3.10): de una rama que se puede instalar y publicado en php.net
            full=$branch
            branch=${full%.*}
            if ! awk -v b="$branch" '$1 == b { f = 1 } END { exit !f }' <<< "$releases"; then
                echo "PHP $branch no esta disponible, se omite $full" && continue
            fi
            [ -n "$all" ] || all=$(php_all_releases)
            if ! awk -v v="$full" '$1 == v { f = 1 } END { exit !f }' <<< "$all"; then
                echo "PHP $full no esta en php.net, se omite" && continue
            fi
        else
            full=$(awk -v b="$branch" '$1 == b {print $2}' <<< "$releases")
        fi
        [ -z "$full" ] && echo "PHP $branch no esta disponible, se omite" && continue
        [ -e "$BASE_DIR/XAMPP-$full" ] && echo "XAMPP-$full ya existe, se omite" && continue
        php_installed_in "$full" > /dev/null && echo "PHP $full ya esta instalada, se omite" && continue
        selected+=" php:$full"
    done

    [ -z "$selected" ] && echo "No hay nada que instalar." && return 0

    echo "Se va a instalar:$selected"

    if [ $yes -ne 1 ]; then
        read -p "¿Continuar? [s/N]: " answer
        [[ "$answer" =~ ^[sSyY]$ ]] || return 0
    fi

    UI=text
    install_plan "$selected"
}

# rehacer|actualizar <version> [--copia]: con --copia, si su MariaDB cambia de rama (empieza con BBDD
# vacias), antes se guardan las de ahora en ~/nexum-backups
function cli_rebuild() {
    local version=$1
    [ "$2" == "--copia" ] && STACK_DB_COPY=1
    local dir=$BASE_DIR/XAMPP-$version

    if [ -z "$version" ] || [ ! -f "$dir/xamppfiles/etc/pvm-stack" ]; then
        echo "XAMPP-$version no existe"

        return 1
    fi
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        # (7.4.33, 8.0.30 y 8.1.34 sin el parche de seguridad: se rehacen en su carpeta con el)
        if [ "$(php2shell_state "$(php_version "$dir")" "$dir")" == parcheable ] && php2shell_backport "$version" > /dev/null; then
            echo "XAMPP-$version se vuelve a compilar con el parche de seguridad contra PHP2Shell ($PHP2SHELL_DATE)."
            echo "Sus BBDD se conservan."
            UI=text
            install_plan "parchear:$version"
            return
        fi
        echo "XAMPP-$version lleva su version de PHP en el nombre: no se actualiza. Instala la nueva a su lado."

        return 1
    fi

    local full=$(rebuild_version "$dir" "$(php_releases)")
    if [ -z "$full" ]; then
        echo "No se encuentra en php.net la ultima version de la rama de XAMPP-$version"

        return 1
    fi

    if [ "$(stack_fields "$dir")" == "$(stack_versions "$full")" ] && ! php2shell_missing "$dir" "$full"; then
        if [ -t 1 ]; then
            echo -e "\033[1;32mEl paquete XAMPP-$version se encuentra actualizado.\033[0m No hay nada que actualizar."
        else
            echo "El paquete XAMPP-$version se encuentra actualizado. No hay nada que actualizar."
        fi

        return 0
    fi

    UI=text
    install_plan "rehacer:$full"
}

