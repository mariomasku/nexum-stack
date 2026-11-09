# ===========================================================================
# Linea de comandos
# ===========================================================================

function cli_install() {
    local xampp="" php="" yes=0 selected="" b full branch

    while [ -n "$1" ]; do
        case "$1" in
            --xampp) xampp=${2//,/ }; shift 2 ;;
            --php) php=${2//,/ }; shift 2 ;;
            --base) echo "Aviso: --base ya no se usa (las versiones de PHP tienen su pila propia)"; shift 2 ;;
            --si|--yes|-y) yes=1; shift ;;
            *) echo "Opcion desconocida: $1"; return 1 ;;
        esac
    done

    for b in $xampp; do
        catalog_entry "$b" > /dev/null || { echo "XAMPP $b no esta en el catalogo"; return 1; }
        [ -e "/opt/lampp-$b" ] && echo "lampp-$b ya existe, se omite" && continue
        selected+=" xampp:$b"
    done

    if [ -n "$php" ]; then
        local releases=$(php_releases)

        # 8.4 = ultimo parche de la rama; 8.4.10 = ese parche concreto
        local item latest
        for branch in $php; do
            if [[ "$branch" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                full=$branch
                latest=$(awk -v b="${full%.*}" '$1 == b {print $2}' <<< "$releases")
                if [ -z "$latest" ] || ! php_patches "${full%.*}" | awk -v v="$full" '$1 == v {f = 1} END {exit !f}'; then
                    echo "PHP $full no esta publicada en php.net o su rama no se ofrece, se omite"
                    continue
                fi
                item=$(php_item "$full" "$latest")
            else
                full=$(awk -v b="$branch" '$1 == b {print $2}' <<< "$releases")
                [ -z "$full" ] && echo "PHP $branch no esta disponible en php.net, se omite" && continue
                item=$(php_item "$full" "$full")
            fi
            [ -e "${TEST_DIR:-/opt}/lampp-$(item_folder "$item")" ] && echo "lampp-$(item_folder "$item") ya existe, se omite" && continue
            local have=$(php_installed_in "$full")
            [ -n "$have" ] && echo "PHP $full ya esta instalada en $have, se omite" && continue
            selected+=" $item"
        done
    fi

    [ -z "$selected" ] && echo "No hay nada que instalar." && return 0

    echo "Se va a instalar:$selected"

    if [ $yes -ne 1 ]; then
        read -p "¿Continuar? [s/N]: " answer
        [[ "$answer" =~ ^[sSyY]$ ]] || return 0
    fi

    UI=text
    install_plan "$selected"
}

function cli_rebuild() {
    local version=$1
    local dir=${TEST_DIR:-/opt}/lampp-$version

    if [ -z "$version" ] || ! is_fpm_install "$dir"; then
        echo "lampp-$version no existe o no es una version de PHP nueva (los XAMPP no se rehacen)"

        return 1
    fi

    # Una version con un parche concreto (lampp-8.3.10) se queda en ese parche
    local php=$(stack_fields "$dir" | cut -d'|' -f1)
    if [ "$version" != "${php%.*}" ]; then
        echo "lampp-$version tiene un parche concreto de PHP y no se actualiza. Si necesitas otro, instalalo aparte."

        return 1
    fi

    local full=$(rebuild_version "$dir" "$(php_releases)")
    if [ -z "$full" ]; then
        echo "No se encuentra en php.net la ultima version de la rama de lampp-$version"

        return 1
    fi

    if is_stack_install "$dir" && [ "$(stack_fields "$dir")" == "$(stack_versions "$full")" ] \
            && { ! php2shell_backport "$full" > /dev/null || [ -f "$dir/$PHP2SHELL_MARK" ]; }; then
        if [ -t 1 ]; then
            echo -e "\033[1;32mEl paquete lampp-$version se encuentra actualizado.\033[0m No hay nada que actualizar."
        else
            echo "El paquete lampp-$version se encuentra actualizado. No hay nada que actualizar."
        fi

        return 0
    fi

    UI=text
    install_plan "rehacer:$full"
}

