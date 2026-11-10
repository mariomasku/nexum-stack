# ===========================================================================
# Panel
# ===========================================================================

# Elige un parche concreto de PHP: primero la rama y despues la version. Escribe el elemento
# del plan (php: o parche:) o devuelve 1 si se cancela.
function panel_pick_patch() {
    local releases=$1 supported=$2 items=() branch full version date latest
    local widths="10 16 16" states=$(php_branch_states)

    while read -r branch full; do
        [ -z "$branch" ] && continue
        local state=$(branch_state_text "$branch" "$states" "$supported")
        items+=("$branch" "$(fmt_row "$widths" "PHP $branch" "$full" "$state")")
    done <<< "$releases"

    while true; do
        branch=$(ui_table_menu "Elige la rama de PHP de la version que necesitas." "" \
            "$(fmt_row "$widths" "Rama" "Ultimo parche" "php.net")" "${items[@]}") || return 1
        latest=$(awk -v b="$branch" '$1 == b {print $2}' <<< "$releases")

        local patches=() item note dir installed=""
        for dir in $(lampp_dirs); do is_fpm_install "$dir" && installed+="$(php_version "$dir")"$'\n'; done
        while read -r version date sec; do
            [ -z "$version" ] && continue
            item=$(php_item "$version" "$latest")
            [ -e "/opt/lampp-$(item_folder "$item")" ] && continue
            grep -qxF "$version" <<< "$installed" && continue
            note="/opt/lampp-$(item_folder "$item")"
            [ "$version" == "$latest" ] && note+=" (ultimo)"
            [ "$sec" == "seguridad" ] && note+=" [seguridad]"
            patches+=("$version" "$(fmt_row "10 13 30" "$version" "$date" "$note")")
        done <<< "$(php_patches "$branch")"

        if [ ${#patches[@]} -eq 0 ]; then
            ui_msg "Ya tienes instaladas todas las versiones de PHP $branch."
            continue
        fi

        local text="Versiones publicadas de PHP $branch, de la mas nueva a la mas antigua.\n"
        text+="Cada una va en su propia carpeta, con la version completa (/opt/lampp-$branch.Z),\n"
        text+="asi que pueden convivir varias. Todas llevan la misma\n"
        text+="pila (Apache, MariaDB, ProFTPD y Perl) y sus propias bases de datos.\n"
        text+="Los parches antiguos tienen fallos de seguridad ya corregidos: usalos solo\n"
        text+="si el proyecto necesita esa version exacta."
        version=$(ui_table_menu "$text" "" "$(fmt_row "10 13 30" "Version" "Publicada" "Carpeta")" "${patches[@]}") || continue

        php_item "$version" "$latest"

        return 0
    done
}

function panel_install() {
    local releases=$(php_releases) supported=$(php_supported)
    local items=() entry folder release php apache mariadb ftp perl pma md5 sha branch full f
    local widths="14 8 8 9 9 8 10"
    local header=$(fmt_row "$widths" "Instalar" "PHP" "Apache" "MariaDB" "ProFTPD" "Perl" "phpMyAdmin")

    for entry in "${XAMPP_CATALOG[@]}"; do
        IFS='|' read -r folder release php apache mariadb ftp perl pma md5 sha <<< "$entry"
        [ -e "/opt/lampp-$folder" ] && continue
        native_binaries || continue
        items+=("xampp:$folder" "$(fmt_row "$widths" "XAMPP $folder" "$php" "$apache" "$mariadb" "$ftp" "$perl" "$pma")")
    done

    if [ -z "$releases" ]; then
        ui_msg "No se pudo consultar php.net: solo se muestran las versiones de XAMPP."
    fi

    [ "$UI" == "whiptail" ] && [ -n "$releases" ] && clear && echo "Consultando las ultimas versiones de cada componente..."
    local old_branches=0 security_branches=0 states=$(php_branch_states)
    while read -r branch full; do
        [ -z "$branch" ] && continue
        # El ultimo parche va en su carpeta (lampp-X.Y.Z), al lado de las que ya haya de la rama
        local item=$(php_item "$full" "$full")
        [ -e "/opt/lampp-$(item_folder "$item")" ] && continue
        php_installed_in "$full" > /dev/null && continue
        IFS='|' read -r -a f <<< "$(stack_versions "$full")"
        local label="PHP $(item_folder "$item")"
        case "$(branch_state_text "$branch" "$states" "$supported")" in
            "sin soporte") label+=" *"; old_branches=1 ;;
            "solo seguridad") label+=" +"; security_branches=1 ;;
        esac
        items+=("$item" "$(fmt_row "$widths" "$label" "${f[@]}")")
    done <<< "$releases"
    [ -n "$releases" ] && items+=("otro" "$(fmt_row "$widths" "Otro parche" "elegir una version concreta de PHP...")")

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "Ya tienes instaladas todas las versiones disponibles."

        return 0
    fi

    local text="Versiones que puedes instalar (las que ya tienes no aparecen).\n"
    native_binaries || text+="Este equipo es $(uname -m): no hay XAMPP y MariaDB se compila (tarda mas).\n"
    text+="XAMPP: paquete oficial completo, para proyectos antiguos.\n"
    text+="PHP:   pila propia sin XAMPP, con el ultimo parche de la rama. Se compila.\n"
    [ $security_branches -eq 1 ] && text+="       + Rama con solo parches de seguridad (sin correcciones de errores). Las demas son estables.\n"
    [ $old_branches -eq 1 ] && text+="       * Rama sin soporte de php.net: solo para proyectos antiguos.\n"
    text+="Otro parche: una version concreta (p. ej. 8.3.10) en su propia carpeta.\n"
    text+="Las versiones de PHP tienen sus propias bases de datos, vacias."

    local selected
    while true; do
        selected=$(ui_table_checklist "$text" "$header" "${items[@]}") || return 0
        selected=$(echo $selected)

        # "Otro parche": se elige la version y se suma a las marcadas
        if [[ " $selected " == *" otro "* ]]; then
            local patch
            selected=$(echo " $selected " | sed 's/ otro / /')
            patch=$(panel_pick_patch "$releases" "$supported") || continue
            [[ " $selected " == *" $patch "* ]] || selected+=" $patch"
            selected=$(echo $selected)
        fi

        [ -n "$selected" ] && break

        # Aceptar sin marcar nada: la fila resaltada no cuenta, hay que marcarla con Espacio
        ui_msg "No has marcado ninguna version.\n\nMuevete con las flechas hasta la version y pulsa Espacio para marcarla\n(aparece [*] a su izquierda). Despues pulsa Intro para aceptar."
    done

    local xampp_selected=$(printf '%s\n' $selected | grep '^xampp:' | sed 's/^xampp://')
    local php_selected=$(printf '%s\n' $selected | grep -E '^(php|parche):')

    # Resumen
    local n_xampp=$(printf '%s\n' $xampp_selected | grep -c .)
    local n_php=$(printf '%s\n' $php_selected | grep -c .)
    local needed=$(( n_xampp * SPACE_XAMPP_GB + n_php * SPACE_STACK_GB ))
    local summary="Se va a instalar:\n\n" item
    summary+="$header\n$(printf '%*s' ${#header} "" | tr ' ' '-')\n"

    for item in $xampp_selected; do
        IFS='|' read -r -a f <<< "$(xampp_fields "$item")"
        summary+="$(fmt_row "$widths" "XAMPP $item" "${f[@]}")\n"
    done
    for item in $php_selected; do
        full=${item#*:}
        IFS='|' read -r -a f <<< "$(stack_versions "$full")"
        summary+="$(fmt_row "$widths" "PHP $(item_folder "$item")" "${f[@]}")\n"
    done

    summary+="\nCarpetas:"
    for item in $xampp_selected; do summary+=" /opt/lampp-$item"; done
    for item in $php_selected; do summary+=" /opt/lampp-$(item_folder "$item")"; done
    summary+="\n"
    [ -n "$php_selected" ] && summary+="Las versiones de PHP se compilan y tienen bases de datos propias y vacias.\n"

    summary+="\nEspacio aproximado: ${needed}G\n"

    if [ -n "$xampp_selected" ] && [ -n "$(active_dir)" ]; then
        summary+="\nAVISO: el instalador de XAMPP necesita /opt/lampp, asi que la version\n"
        summary+="activa (lampp-$(active_dir | sed "s|^/opt/lampp-||")) se parara durante la instalacion de XAMPP\n"
        summary+="y se volvera a activar al terminar. Las versiones de PHP no la paran.\n"
    fi

    summary+="\nLa version activa no cambia. Las nuevas se activan con\n'Cambiar la version activa'."
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se hara ningun cambio."
    summary+="\n\n¿Instalar?"

    check_space "$needed" || return 0

    if other_lvm_running; then
        ui_msg "Hay otra ejecucion de lvm en marcha. Espera a que termine."

        return 0
    fi

    ui_yesno "$summary" || return 0

    [ "$UI" == "whiptail" ] && clear
    install_plan "$selected"

    [ "$DRY" -eq 1 ] && return 0
    ui_yesno "¿Quieres activar ahora alguna de las versiones?" && panel_use
    return 0
}

function panel_use() {
    local items=() dir active=$(active_dir)

    for dir in $(lampp_dirs); do
        local mark=""
        [ "$dir" == "$active" ] && mark="activa"
        items+=("${dir#/opt/lampp-}" "$(stack_row "$dir" "$mark")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas."

        return 0
    fi

    local version
    version=$(ui_table_menu "Elige la version que quieres activar.\nSe parara la version activa y se arrancara la elegida." \
        "${active#/opt/lampp-}" "$(stack_header "Estado")" "${items[@]}") || return 0

    if [ "/opt/lampp-$version" == "$active" ]; then
        ui_yesno "lampp-$version ya es la version activa. ¿Reiniciarla?" || return 0
        [ "$UI" == "whiptail" ] && clear
        control_lampp restart
    else
        [ "$UI" == "whiptail" ] && clear
        use_lampp "$version"
    fi

    [ -t 0 ] && read -p "Pulsa Intro para volver al panel... " _
}

function panel_register() {
    local name
    name=$(ui_input "Hay un XAMPP sin registrar en /opt/lampp.\nNombre de la version (p. ej. 8.2.12):" \
        "$(readlink /opt/lampp/bin/php 2> /dev/null | sed -n 's|^php-||p')") || return 0

    [ -z "$name" ] && return 0
    [ "$UI" == "whiptail" ] && clear
    register_lampp "$name"
    [ -t 0 ] && read -p "Pulsa Intro para volver al panel... " _
}

function panel_databases() {
    local items=() dir version owner count active=$(active_dir)
    local widths="10 12 30"

    for dir in $(lampp_dirs); do
        version=${dir#/opt/lampp-}
        owner=$(data_owner "$dir")
        count=$(db_names "/opt/lampp-${owner:-$version}" | grep -c .)

        local data="propias"
        [ -n "$owner" ] && [ "$owner" != "$version" ] && data="las de lampp-$owner"
        [ "$dir" == "$active" ] && data+=" (activa)"

        items+=("$version" "$(fmt_row "$widths" "$version" "$count" "$data")")
    done
    version=""

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas."

        return 0
    fi

    while true; do
        version=$(ui_table_menu "Elige una version para ver sus bases de datos." "${version:-${active#/opt/lampp-}}" \
            "$(fmt_row "$widths" "Version" "BBDD" "De quien son")" "${items[@]}") || return 0

        local cols=$(tput cols 2> /dev/null || echo 80)
        ui_msg "$(databases_text "$version" $(( (cols > 110 ? 110 : cols) - 8 )))"
    done
}

# Ultima version de PHP de la rama de una instalacion (vacio si la rama ya no tiene soporte)
function rebuild_version() {
    local dir=$1 releases=$2
    local php=$(stack_fields "$dir" | cut -d'|' -f1)

    awk -v b="${php%.*}" '$1 == b {print $2}' <<< "$releases"
}

# Rehace una version de PHP nueva con la ultima pila de su rama: actualiza los parches de una
# pila propia o pasa a pila propia una version antigua copiada de un XAMPP
function panel_rebuild() {
    local releases=$(php_releases) items=() dir version full f state

    if [ -z "$releases" ]; then
        ui_msg "No se pudo consultar php.net. Comprueba la conexion a internet."

        return 0
    fi

    [ "$UI" == "whiptail" ] && clear && echo "Consultando las ultimas versiones de cada componente..."
    for dir in $(lampp_dirs); do
        is_fpm_install "$dir" || continue
        full=$(rebuild_version "$dir" "$releases")
        [ -z "$full" ] || [ "$dir" != "/opt/lampp-${full%.*}" ] && continue

        local new=$(stack_versions "$full")
        if ! is_stack_install "$dir"; then
            state="sobre XAMPP"
        elif [ "$(stack_fields "$dir")" == "$new" ]; then
            state="al dia"
        else
            state="actualizable"
        fi

        IFS='|' read -r -a f <<< "$new"
        items+=("${dir#/opt/lampp-}" "$(fmt_row "$STACK_WIDTHS" "${dir#/opt/lampp-}" "${f[@]}" "$state")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones de PHP nuevas que se puedan actualizar (los XAMPP y las versiones\ncon un parche concreto, como lampp-8.3.10, no se actualizan)."

        return 0
    fi

    local text="Elige la version que quieres actualizar. Se muestra la pila con la que quedara:\n"
    text+="la ultima de su rama de PHP. 'actualizable' = hay parches nuevos;\n"
    text+="'sobre XAMPP' = version antigua que pasara a tener su pila propia;\n"
    text+="'al dia' = ya tiene todos los paquetes en su ultima version."
    local new
    while true; do
        version=$(ui_table_menu "$text" "$version" "$(stack_header "Estado")" "${items[@]}") || return 0
        dir=/opt/lampp-$version
        full=$(rebuild_version "$dir" "$releases")
        new=$(stack_versions "$full")

        # Con todos los paquetes al dia no hay nada que actualizar: se avisa y se vuelve a la lista
        if is_stack_install "$dir" && [ "$(stack_fields "$dir")" == "$new" ]; then
            ui_up_to_date "lampp-$version"
            continue
        fi
        break
    done

    local old_mariadb=$(stack_fields "$dir" | cut -d'|' -f3) new_mariadb=$(cut -d'|' -f3 <<< "$new")
    IFS='|' read -r -a f <<< "$new"

    local header=$(stack_header "") ask_copy=0
    local summary="lampp-$version se volvera a compilar con la ultima pila de PHP ${full%.*}:\n\n"
    summary+="$header\n$(printf '%*s' ${#header} "" | tr ' ' '-')\n"
    summary+="$(stack_row "$dir" "" "Ahora")\n"
    summary+="$(fmt_row "$STACK_WIDTHS" "Despues" "${f[@]}" "")\n\n"

    if is_stack_install "$dir" && [ "${old_mariadb%.*}" == "${new_mariadb%.*}" ]; then
        summary+="Conserva sus bases de datos (misma rama de MariaDB, ${new_mariadb%.*}).\n"
    elif [ -L "$dir/var/mysql" ]; then
        summary+="Ahora usa las bases de datos de lampp-$(data_owner "$dir"), que no se tocan.\n"
        summary+="La nueva version empezara con bases de datos propias y vacias.\n"
    else
        local count=$(db_names "$dir" | grep -c .)
        summary+="MariaDB $new_mariadb no usa directamente los datos de MariaDB $old_mariadb, asi que\n"
        summary+="la nueva version empezara con bases de datos vacias (ahora tiene $count). Despues\n"
        summary+="se pregunta si guardar antes una copia en ~/nexum-backups/. Para llevarte alguna,\n"
        summary+="exportala antes desde phpMyAdmin e importala despues.\n"
        ask_copy=1
    fi

    summary+="\nLa compilacion tarda 10-20 minutos y mientras tanto la version actual sigue\n"
    summary+="como esta. Solo al final se sustituye"
    if [ "$(active_dir)" == "$dir" ]; then
        summary+=": como es la version activa, se parara\nunos segundos y se arrancara la nueva.\n"
    else
        summary+=".\n"
    fi
    summary+="Los proyectos de /opt/htdocs y los vhosts de /opt/config no se tocan."
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se hara ningun cambio."
    summary+="\n\n¿Actualizar lampp-$version?"

    check_space "$SPACE_STACK_GB" || return 0

    if other_lvm_running; then
        ui_msg "Hay otra ejecucion de lvm en marcha. Espera a que termine."

        return 0
    fi

    ui_yesno "$summary" || return 0
    # (sin copia, las bases de ahora no se podran recuperar: la casilla, desmarcada de partida)
    if [ $ask_copy -eq 1 ] && ui_yesno "¿Guardar antes una copia de las bases de datos de lampp-$version en ~/nexum-backups?\n\nSin copia, no se podran recuperar."; then
        STACK_DB_COPY=1
    fi

    [ "$UI" == "whiptail" ] && clear
    install_plan "rehacer:$full"
}

# ui_up_to_date lampp-X.Y: aviso en verde de que la version ya tiene todos los paquetes al dia
function ui_up_to_date() {
    local message="El paquete $1 se encuentra actualizado."

    if [ "$UI" == "whiptail" ]; then
        WT_GREEN=$message ui_msg "$message\n\nTodos sus paquetes (PHP, Apache, MariaDB, ProFTPD, Perl y phpMyAdmin)\nestan en la ultima version de su rama: no hay nada que actualizar."
    elif [ -t 2 ]; then
        ui_msg "\033[1;32m$message\033[0m\n\nNo hay nada que actualizar."
    else
        ui_msg "$message\n\nNo hay nada que actualizar."
    fi
}

function panel_remove() {
    local items=() dir version active=$(active_dir)

    for dir in $(lampp_dirs); do
        version=${dir#/opt/lampp-}
        local mark=""
        if [ "$dir" == "$active" ]; then
            mark="activa"
        elif [ -n "$(data_users "$version")" ]; then
            mark="en uso"
        fi
        items+=("$version" "$(stack_row "$dir" "$mark")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas."

        return 0
    fi

    local text="Elige la version que quieres desinstalar.\n"
    text+="No se puede desinstalar la version activa ni una cuyas bases de datos usen otras ('en uso')."
    version=$(ui_table_menu "$text" "" "$(stack_header "Estado")" "${items[@]}") || return 0
    dir=/opt/lampp-$version

    local blocker=$(remove_blocker "$version")
    if [ -n "$blocker" ]; then
        ui_msg "$blocker"

        return 0
    fi

    local fields
    IFS='|' read -r -a fields <<< "$(stack_fields "$dir")"

    local summary="Se va a desinstalar lampp-$version (PHP ${fields[0]}) y se borrara la carpeta $dir.\n\n"
    local own_dbs=0 names=""

    if [ "$(data_owner "$dir")" != "$version" ]; then
        summary+="Sus bases de datos NO se tocan: son las de lampp-$(data_owner "$dir"), que sigue instalada.\n"
    else
        names=$(db_names "$dir")
        own_dbs=$(grep -c . <<< "$names")
        if [ "$own_dbs" -gt 0 ]; then
            summary+="ATENCION: sus bases de datos propias ($own_dbs) se BORRARAN con ella:\n\n"
            summary+="$(columns 66 <<< "$names")\n\n"
            summary+="Antes de borrar podras guardar una copia de todas ellas.\n"
        else
            summary+="No tiene bases de datos propias (aparte de las del sistema).\n"
        fi
    fi

    summary+="\nLos proyectos de /opt/htdocs y los vhosts de /opt/config no se tocan."
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se hara ningun cambio."
    summary+="\n\n¿Desinstalar lampp-$version?"

    ui_yesno "$summary" || return 0

    local backup=0
    if [ "$own_dbs" -gt 0 ]; then
        ui_yesno "¿Guardar antes una copia comprimida de las bases de datos de lampp-$version?\n\nSe guardara en ~/nexum-backups/ (se necesita espacio libre en tu carpeta personal)." && backup=1

        # Sin copia, se pide escribir el nombre de la version para confirmar
        if [ $backup -eq 0 ]; then
            local typed
            typed=$(ui_input "Se borraran sus bases de datos ($own_dbs) SIN copia y no se podran recuperar.\n\nEscribe $version para confirmar:" "") || return 0
            if [ "$typed" != "$version" ]; then
                ui_msg "No coincide. No se ha desinstalado nada."

                return 0
            fi
        fi
    fi

    [ "$UI" == "whiptail" ] && clear

    if [ "$DRY" -eq 0 ]; then
        echo "Se necesita la contraseña de administrador (sudo):"
        sudo -v || return 0
    fi

    local ok=1
    [ $backup -eq 1 ] && ! remove_backup "$version" && ok=0

    [ $ok -eq 1 ] && remove_lampp "$version"

    [ -t 0 ] && read -p "Pulsa Intro para volver al panel... " _
}

# Icono del acceso del menu (PNG 256x256 incrustado, para que el instalador siga siendo un solo archivo).
# Lleva el nombre de la aplicacion para que GNOME no siga mostrando el icono antiguo de su cache
ICON_FILE="$HOME/.local/share/icons/lampp-version-manager.png"
OLD_ICON_FILES=("$HOME/.local/share/icons/lvm-instalador.png" "$HOME/.local/share/icons/php-version-loader.png"
    "$HOME/.local/share/icons/php-version-manager.png")
ICON_PNG_B64='
iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAAAABHNCSVQICAgIfAhkiAAAIABJREFUeJzsvXecJUd57/19qrr7hMlp
Z3NQWFAAIQQSksASwWQwItrXluEaAcZgwsXGgC8Xrs177QsGbMBgjDGYZEww2NiAA+Y6ALZJMiAESEhotUEbZ3YnnHO6q+p5/6g+
M7OrzTNnZ1Z7fvtpTWvmnO6q7qqnnnrC74Euuuiiiy666KKLLrrooosuuuiiiy666KKLLrrooosuuuiiiy666KKLLrrooosuuuii
iy666KKLLrrooosuuuiiiy666KKLLrrooosuuuiiiy666GLFQJa7AQBPfd17SNeswaxdzz9/fzdgO3IfBYry6lbBqOKdpzk1i282
EVVEBJHOPBYTHIOtabxYvGSIwOq6QaZ28s0P/s+O3HOl4zHvfZnZPrWvvnnV6vrtP/7h1D04n5vO37eiIAGKRpN8tgGqZEHoyz0m
dG5atEJOhYQkF5h1bqjaF777iX/r2P1OhGTZ7rwAI2s38G8TjcpdEzse5+urRlU6IwAAMICCKBiFxEPLT6E6G/+uEiVFB2A1kGiF
oCktW0cJzBzcGwYLc8svvvlT3/zQq58ZOnPnlYnHf/CV7Di0/5HbZ/e9afu2vYNZojvy1EwGIx16A/NoKpgALgRCqwCEIiiHvMeY
zt1e1eFR6pqEnoHaJy669NK//O4n/q3j/T0WVoQAuOHZj+f7f/UfdtvB4qoAv2K86ZEAXgBRBAUVVCSeLwKqcX4bhRBAvaJOIRgQ
gyk6+S6EGemlsDWCqQFKyLwenNn73a9945Yn/vGXdux54aPXdfD+Kwdv3/aX/Ot/fXvL3qm7fnump3WlWox1en8NFtW2CrC070IB
kXhiVDEKVjw+tJAgBIFmJXRULxYC3nkym+6vVOq/PzA0uGyTH1aIANg8ZnnK/UZnb//mHb9/IJHrkunkmqqry5RxUHMkzhEweJuA
Bowu4plFWUIQwCq5KhhT/hJ8R9VPwZPF+4lDQ4EvmjRbPGAq6HM/8LG/fhvgO9mClYKvfv/m9Nv7b3v+/p6Zh+BaRnJLkAQrKVHM
KzqnCCxUjITTn6HKnHavigp4CXFPqIG5wXHaw0vnm6bCvfQYo2gFRJOQziafG+wd+Nb7Xvi7p3uzJcEZ2G2dGA8UoTYxyYjO7q9k
1fej+VQzVTVZggaDElf/uacrp3lw76GjC34zdybSmQMpx1dA1UFwYCyONJ1p+udv27lny+s+dPOSP9+Vhrff9UXu3rnr8mnXehEm
JFGrC0jQeCYLJv+93uPpP38Vg9IeTwuuWd7ndIfV/GWkFCBydBGlIM6oNvwtAz19v/fU65/QWtIHexpYEQIA4FU/cxUPXbc5jM00
PpXV5CN5pem9eGwwIBY1BsJRpOrZAo3/EQJxsIe4BzEJQTOhOnT+wYZ/yRf+4UvZMre0o0je9njuaUyt2maaL5ut6DAq0eZqFFUP
OFQ8KiEedMgs0oFxJAsVAEBLQTZ3IJrNUAya+rsG+vu+/5qnvnDpG3GKWDECAODGR1/OqJudaoTpP6Xidop4kiCoRsltw2ItAMsP
QRH1oB4UglqCrdIMqQ1Z3y8ePDjx0Ce99G3L3cyO4Ip338gLrn0qf33zlx+xt5I/fdZ6SUqbDBIQ9QTxBAlzB2gpOw0rbLgeHQqi
CmhUPKwgJiogVkWHQv1rl6ze8pevf/mrV8RQXlFP9PGjhlc8+0ouHLTb0nxqSsQBWqrNUU0822EAE3xU/yUQVMFYClJpSWXwYIsX
377rUM9nvnlwuZu6pPj49n9n5JItfPU7/9mzfXbfDa5GldRIIO65RZQgHnwL1AEB1BMWqnyler2SEZtbbgEEjDEQFKNC5mVyKKn9
bjXYfU9ec83yNrTEihIAAFs3DHPDFfeTwWbz37MibzlTAJ5EPSpu0V6AZUM5bkNQQghR3VWP4Cnt03hSc9D3PnWyITe+8wOfWNkj
/RTxB3/xZ4QDTdlTHLyRCk8lbwpE5wsoGhQxHownRmtE4b8QZuUN1xOj8CQYtUXQTOWvegb6v/yF/+/Pl7tVc1hxT/Rqa9h15549
fU39zarL/zkYr0ggCw6LP3sEgC48NB5AUEVVgTj5rRZxxVMHYnDZaO+hIn3x7j37x9/72W8vYweWDm+7/a954BWXsX9yZnx/v7y4
ZYreujPY3EUBoGBDgHLPb4KD0BaMbZwt8jC+9NLkgwbV1AtVL5Mbx1Z9/Morr1h2w99CrDgBAPCBGx7M+PCaPRKK91pxs9KePBIW
uIbOJpSDd6FAIPqEReMRVV4FKlJQveieA1PP+cBn/mlFvp9TxTs/80G++5/fso3Zxn/3Nb1ItRApPMYm8X2WQTnzDyg+k9h5nTeu
nQWvvr1DmTcGCgYbBrLez2xes+Gf3/2s3162th0NK3aAffVlD9UNtvWlsWbzH21ItCEZQRLOnpUgQhQSBeMVCgfEfaGVBEOKikWx
gIkCILRwUk0OSf/LXdb/kFe/b/nCRJcCP//Xv8slF1zM5GDrvJ39M88LXhNnLbOpUKhCEIIRCmMRl2CCQTDxUbiAdQGC4kPA6723
BSsRNiiJj1Z/khSn2XdX9a3/vSvOf9CKWv1hBQsAgPPGVx30Uwf+sOpbBxEBkx7mt1/xKK3BQRWCzo/dBbkGutCLrIoJBWDEabpp
xz37XvbdH9xeO9PNXir8U34HX27eiZtuVZve39QSv6XthFdz76ksukBTOuwkYAis6Mm/IGwBA95GQ2CSS9EjlfesP+/8H77xCa9c
xgYeHStaAHzm+VexYXTwKz1u6kvV4FSDZUVrAEdGKIrEqLZQWvtPhGgWiz6jtMfsmw1Pvv2uXT/95Nd8uBOt7The8/63cKldzV6b
P2kidS/0hOTEczjq+6bcDkQvQHvLtPJhguDEEKxRExIdDNWvXrFx61/e+MSnrUjptaIFAMADt6ydHa2Zd9RC4y4JfuUHArUNfu29
YNvoF07GhakYVaxJQC2uMtS/e6p47V3bdo1/7pZmR5u91Pjs3q+zcctGGq2Z8buKidce7PUDeoI0OyOUNp4y/2Nu8rddwCv45Ut8
11ZBxChiSX1yYCCpv7ZOuu+ZGx+x3C08Kla8APjTZ1xCqs2v1YupT9TdjDNnUSyAiMyv/CeVYixx6HsXzzWThum7YufE7LPf/r6P
nA0L4Bxe/udvozpVyO7Jfc8+kOUPVNuSJC1N/sdEnPiBAKJYAkbnIwJXsgE4Rv4BAlaFpLCh0jJ/laj91mdf977lbt4xseIFAMDF
m9cWm/uSDw8Uk9us+pU7Co7A3OoPC/IBjvsNFBt5CULMCSq0kkx7c9Odd+8c/91PfaOzDV4i/OmBr/Lyn3ke9+SHLjtomy/C+gSB
IriT+Hap+s/99EjQUhlYuVpA1FgEZ1EbDH2t5Ef9Un3rYx/+qHy523Y8dDDxfunwnU/+MT/9/Fcc2DNxwEya+pXeJLW2mh29SKUR
7STWSGE+4au95aaZQ+6YSzY+XUKQhckn7bxjH+ZvLPPtnDP9hYA2WuA9YFBJMHiEIiZAiRGTyLCbOTD549tu+9q+W/9lZc6ABbj1
AQFp0vv9yR3v3lvNrw7aMoa4koM5jHBFvEcbTSTE7Y+atoYniBhCuawK8bmK2CPet87bVk/CSjD/WY3UEEWBNltzrsbjG5nLUTP3
Y64l7YuiRqi0bDGuPW9+0JaLPv9nv/p7K/p9nRUaAMDjr3mwmzXV91gNH7HqHRJfYZibxcScgeV63OV9jQhlcNt8THj5R3PEZ49E
HOSm9B2HGCdgLMHZJCQ9z+0d3bT64S95f2f7sUg86n0v5QG9G5lys48shtOHt9LcZApJrnMT9PivSBZ8okye0hA1gbmoyfh3ndO7
42ej3tDpAaBzP0SllPPzEsEiJC58b7R/4CMvv/GmFZ/afdYIgGetF4J3jbHG3g8M5VMTqICtoEYQPKqCasaydkkV8R4TAiZ4gisw
EpNCTGnImqO6kJKToH0oWFUSKbMeTAWCkviCiljZsOXy8+/YPvPC/ffsqdx8z8pcVP7e/4gft/axZ2ai9+adt7yomc70j/bXSUPA
JFWsS+LqX/b5yLU2vkOLkMyF/RoBYzxGCpAc8Cg6N/mlfHgxiegMxAkYQLQMXDKRWcbGSCajgXrLFMNJ/b3nbzlv3/VbHtbZtiwB
zhoBAHD365/CWE2+XwuzX6j4VlAfgKRUm9sK/DJNjgURYLIg9BcW7AyYPxZ+Zw4h4IsWklh8CIgYMmvYcsFW7rj9zqTw+src5S/4
zf/7xyvyvT3WbuXSvg1yYPLgEw+R/9TE9IQEPAPDwxStnGDT+ajoo7ymuI4Kpnybghy+qwICHsWX24nyewvzcE8Wp2tSLds+l5dk
DWKiEEqx2hvSf734/Pt96uUveMnKlNJHYEUOpOPhQfff0qpp8521fGqvCU6FlEClfKE5K8FI5EMgnJTb7wiIYBOLOIc1QjXLWL9p
E7fdfjtqElpOe/c3zS//ZG9j/HM/XP5+Hok/m/ga6Uj/hZOh+bq8ZnpzAgcPHsJpYNWqMYwP8xPotO6gSHBImS3Y9g6InvYFT/Xu
aGmTiEIn0odFWZ8ihdln1b62v9Z74KH1+3e+QUuAs04AvO9plzFSr93cExrvq/uW0yCoJASBhDOcLXjESt/+nR7t9ye8VrkTCB4x
UK1WGV8zzraf/ASMwTkHtirToW/rwYbc9PY/+viKM+B+9P/9tfn2Pbc/7WCvXpJXRNQYgjXsOzhJQBkaHIwqeykEpO3qp1zhT2JV
ViJpiOAR8czl3Z4BxKlv5v5HJL5nISVpGT9SHfrMqrHVN//5K95zRtqzFDjrBADAJZvXuLGqeX+fm/ph5hradpkFjswgO8NQCCEg
xHh/cxJuP5skEBRrDEZAjFJJDKvHx9i7YwetwpE7xZuUXA2a9icTU+4X796zf+sr3v+fZ6JXJ4Xfv/XTNKcOXTCZzD53tupsjNsX
fACxhn0H9qMExgYGqSpUjaXi/GFT98QCQFFTqv8SEAPzAUKHba46iNIbASABg2BbQXtcenMvlbdefemVxRloxJLhrBQA733mFWxd
t2rboM5+qMdPF/joag3aWUbX40K19FMzV1vgRDUGVBXNc0ySoN4jIlSsYf2GDezYvp2W94Q2RboYRAyqRpqabd69f+qXv/BPX0nP
RNdOBv96+3f69hbTb5/Nivur9UKItM4Wiw+KJJbJiQMQlKHhYVwrx6QpRzJwn/D1SYDSDhD0TFj9D7v5nA85Unwp4gPVkOb9mr1n
Tf/o7e/6hf91BtuzeJyVAgDg+svuF7aM9X+iVkz9yOJUUTRJlidOsFT5JYRTUkBEBJOmiHeIMVSzjA0bNvCTO+/A5/kCY+K8+VB9
gc3qdqawz9l/cPqKn/ut5SeXePonXs8PDux8zPZ05uFF6o3gMV7JnIIHNQYXPBg4ODGBusDY2Cq0rS2d9Ba+7VL1SPBo8Ed87wxp
ATJvcDY+aC3Id0b6+j/72pe+auUZZk6As1YAvOiBg2zetOnusYHquzKZPUjRxEgFq2UwaZtXLjqNlig+YEFs+sILKhAiq82cheso
x70i2lXREJN/qtUK46vH2b5tW1wxjUG9LggeElQV8Q7ng6jJxnLnf1eS7ILvNpZv3P2z/oRp31g9ERqvna75PgQIMQVaAiX7kUIM
BULFcGByAlVlcGhofpukzGkDbd96+19Y4OFv5woY9Zgw7w2I3pcOd1bbAiigZRCaJTnYU6u98/LLH3TgsWuu7HADlh5nrQAA+Lkn
bAm2MvGhWrLzH21WBNOskLk4AtUGNFHCgsiySAu9OMTwI53LVrMoNvgyki8OYjnGEeWG0ObBw0ffccXCurWr2LNrGw0PnoSChEKS
uQDztmExmISgnpBgZqlc+6Wv/fDpr/qff7Fs7/HNf/Fu+XFjz1P21/LLwAvBELC0jKGVCGrNnOBzYigk4JNoEwgo/X39oJD4mEiz
8AUFYnGYIEKQkho+SEwblmgQFO8hBKwXErXzKcUdgCFQ0RyhCakgmoZe3/P3g+nAp17wnOeddas/nOUC4OEiPPiS9Y11WeV9A+r2
O9PS3Ei5b7ZoMNhgkJJN2IsuLaekKurbLr8Ffv/jHO1PqCpGIE0S1m/cwF13b2O61SLMCaoFDvC5rymRKNUDlqBV22yaX9y1fc/4
33z7zIecf3j2G9x9cN/wdN68yYUijRM09u/wjs/3wVgTPR2J5cDEBIgwOjqKWSCcPUSNgCMV+sOfpELJqFRqCMcKMFgiRCHmUWPR
YEmLbN9Atf8t1135U42r6xd37L6dxFktAADed93D2NQz/OXq7NSbrZnMiwSQBNUEExKst1G1NAHs0nsJNLTdfifefbbnQnvQ9tTr
rFmzhrvu2lZeR07QPAUpQDyoBa2Lc9Wt04dmb/qjD3zsjLsF//57/17ZTeOm6SoPFEQkHC7m7gUtyVGMIXiPGMPU5CQmBIZGhjEi
MRFKI2Ni21V4+EOZD/2Vua2Yj5TinEyy0SIgBp8YrM3Ipr0fT/o+c/76jf/1Bz/72s7et4M46wUAwOMvv7Lo6eGDWTL9IxGvYJBg
EG9JgsWoicYmWUKbcXvreq/QtvkJoOWq1D6ioTDGKtTqdYaHh7ln9x688ziVWPzkuK5DRcWVlnBD0Are9CYHZ/3z7th252W/8Fsf
WKrenRC//JV38b27b3/soT5e06ppJShYtSeMf9C2TcAaggZygX17diMGRkeGMWJINSbqtGkCjTJndFu4zzcoAYdqQHFljMDhz1yX
xvgTIUqwFrxo3dduvmB8w1ufdO2jzyq335G4TwiAl1zew2WXbjowat2Hq5oXtjUbV9kQynWirDUHLFYDkCOuYoxEn3/pxz8Myvyw
lOi8qhihN0tYNTbM/t27aTabeDEEVYKcKJlJmFOMS3XCm1SaUts8Vciv3Xb3RHVRnTsFfPfu26rbZvb+t0aWD3jjxUI0Wh5PA4hS
GMpn4Upruk9Tdu/dixPD8PAwiGBUSY0t1fx520pkDJxPoBD1KAVKEbWAUsAs+eRvQ4VqnuQDpvYe0wy3v/zaG5f+HmcQ9wkBAHD1
+evDJSNjH++bnf5GjVxFcwRHYdvc8yxJXZGFFnwJh/v9jzb4BcGIEMq5kaQJ42vG2bNjF41W5Ihs1z1UzAn2EQKaIdiYGWdygih5
UjP7m8kT7trdvPrRr/zI4jt5Ajzx8/9b7j6459oGjceDEzTghQVVfY/T/rZto/0ba2OyVJKwb+8eRJWxkREshpAXh20HzNxV5hN/
1YBIwEiADicDqYJ1VpPCfGe0b/CzL3jWc89Kw99C3GcEwP+4YIzhdODuVVn6J3XfLPANfKI4E3BSqo6BewWenBbmaL70hCqvEaGt
h/TW64ytGmXX9u24olmWqi4rE9MufXW8PbSBUEVDgooHm6MmJ9gMbwYHphrpr2+/c1vfEvTwmPgnvZNKb+8FE1V9SyP1A8YF8G3t
6sQW1oVcDIpSOIeqEpxDRDh0YAITYHR0FJumJMgCIXBEvLAo1ihqNHoEtLPZt6Jgm2FyfGD4nZdfctmB51z+xI7e70zgPiMAAF72
7Et41EMv+ofhVL+SmRCCBUzptgsSC40uMlBEiDngBEX13iqF0vZjl/+vsZhJvV5jeHiYvbt30yxygrFgzILxfLJBLAllPWugIBC3
oIVWxWnt2snJyceM/vRrFtXH4+Fd/+8j8tVbv/nYmYq/1FiVxGtJ21XGxp8Acti5kKZpLJduYpS9Q9l3YD/OO4YGBxAgVSVpP1jm
4wTmrwLQZhEKZURmOFw4Kyd0Ec5v7tpHea3yOlZtGEjqn+ztqX/iNTedfUE/R8N9SgBcKUK/aW4frvs3iQkTYDFBqBae1AueyoKM
/NOARmeC8XHVO/LxRXs0OBG8gCNQNUJfZlk9MsCBe3YwWyhqKwRJItn13JgM5bePN64UaMZB6TJwFQiWoI4gntzYvoO18dePrNm4
7q2fvvX0+3kMvHXn59ljDj3YZc1fqXiXSBBcYvHWgAS8nIQVXturfzxc8HG/TqybXBAoBA4c2E8QYXhkFMFgglKRw42M7ScWn2OC
GoOEJkKB4DHaTg4zgEXFcHzWIC3j+12MxFBHRRQbAqlaTX22e6OMv+fpVz2+dYGMnf6DXEG4TwkAgDddv4UNWzZ+dVXm/y510w6U
wlQoTBIzyBa5RwxzFN/Huk7MYScoIkKSpaxas5rdu+6h2WrGzcBRLf0nUfHgsHA3E7cE7W8JqIoUoXLpxJ59r/jc5z9fOeXOnQCf
/8qXq9t27HxJU9z9g0RfxLFsH8fDMb+hRAYkom1g/959hOAZHRvFiqEoorZzvDiBUAYIKYFgFkQUSltDOD6sxusokbAliCEzKam3
RU9We0c60vPd33zKS06pvysZ9zkBAPDQS85vrkmLN4y6yVttcFokVZxNEClYbCzgQr//0SASg1cFpa/ew/DYGDu376TIczDJou59
YhignjRactPO3buveeXbP7lkV37htz7Erpnph08UzRvy1EgugTb3mUA0ii6BUhy8QwUKH8AYDk1OgPeMrBrDZin2MJvAveMEIh1j
WXINoutuwd+P5wgWFawXjII3QrCCA0xINGvID9b0DH/0CY97woqn+ToV3CcFwKu21LhkbPCONdL6YM3PFhhFTdvsdJqjtJz0C/3+
c2Hscy6nyOZrVKn31BkeHmLf7r00iwJvExDb2VwVEbxmkid9A4ecffHn//XrS1ZV6Ju3/1fPTtP4tZlUB5wJgtEjip0sQccETJqU
adHzW6r9EwdouZyhoUFEZC5OwJeKWHQRxj171ApKG4BoSbs2Z5E5YRPSEAWBiolbhiCYFpPDSc8fbBkY3/GGR/z3xfdzBeE+KQAA
rt26MVx50YUfH2T2X5IwE6IsX0S2mCo4V3LURb9/1PTnE41CCHN+/rGRQfbuvodWXiCSllkDcjKK/ulDFUKBMzWZ0t7HHmwl117z
4ncs+rLP+PhvyNTUvmunkpmHaaoiNro2rSzYUB1hoD8taJnoW4Zsi4nsSg6YPHAADwwPj8Q4gaBkdkGcQPkT8ZGHER/rK4RYeTka
S08cCeoFvBhEDRIsxpnQa6pfTE3ysZf/0ovPnqIUJ4n7rAD47w/cADbdOV7ndwb83onEN1CpnPoEbK/4c6vd4Xn+goCJfn4RIU0T
Vq9Zxe6du8o9P+XkiCWjOmo6FsXYFmoMs6G3/1Cr+toD+5vDX/7h6Y/bv9XbmNTW2ilmf4es6EdDTGgqj8PClxchX4/oSEmaqmAP
twmo96waHcPKseME2g1qJ2yhoR1lcaLb0rKlIFMQb6i6dG/NZG+57upHNB+9+iFL0bkVhfusAAD4oydfzGiP/+pQOPD5ipv1aMYp
l0IQgRCjCo/6sEyZpotS7+lhdGyUndt34IsWbSZQLc2PndX/iZbvMEVQj5oBcQxf05z2z3v169502u/59z79geTHrYkXHqgWDwg4
0aDRM7bw4F45P6eFwzWI6G71C20CYpianADnGBsbO0qcALTdDKFMwTRlotZc+47TxoASrCHEGmVUChN6Sf5y7arx7733+W9aXOdW
KO7TAgDg/DXDzf567deqhn/EeQ0lj5uWQSXt/G5gfgQuWPUl3Dvg5zCFoNzz99TrjAwNsnf3Hlp5QZAEI7GY6fEr4i0txBoIHsRQ
UKlMNbhpckbWvuY9p04f9iv/8m4mG1OX75bmja2KJqbwh83SI41+S63dRMKUtk0gagVOo00gL3KGhwYRINE4waNL8HA/vuh8IPhc
04/5PgSRUlgEtBLM98cHR971iCuvPqvj/Y+H+7wAeNeTrobG7J4a+QczO5urydFYu420sFhVVEpmmZBgQszWMxqwwWO8Iwllrjqx
xmfQUmyEQE1KP/9wPxP37KThAiGpEIwtc9jbIfBahqt2rq+qKYWLfnOR/WjSlEO2/8JJ7X31v33zllN2C96+7yfVfXb611oVt0mw
YrR2mB994Yp9hDH+tCAKpqwQ1D6kFL5SGl1jnICwf+IATpXBsVHUGoyYUreLVn8D81pXEMQb1EEUE76sOjzPFQEWgyEJgUTBeluk
tvaeSqXn1v/zM69aXMdWMO7zAgDgm6/5bzxg7fB3evyhW0WLoAawKa4kmmhrhu0AFWhb9ud/IUT3UCxPxXH9/IeR2ZefPzNKgJaJ
MnHfi4BPKrZRhBsnJvde84tv/OhJX+nl//yHHJo8eM307PTjJLWGIGVJDjjsgS1hx9rhxO2En3bM/zy/4nycgLWWif37mZ2ZjcLY
uWg1lMOv6Gm7baNrkHb7j9EAVSV41Zqp/mB8ZNXnfu6Gn71PRPwdC+eEAAC4YO3YrQM6c1PmGz/C53irhCRBxcb1QhWZY5otcZSA
H7Osfv4TQ8WVIsCCWhQkt9nA/pnWi39w157ek7nG3+htaG9l6z7f+C2X0q+tAtDD4o6WA6qKugJBKZwnYJiZnYnuSBF80AVqSanK
a7u02Hy68DGvL0IgIdF0eqR/6HcuuuB+O15x5bPPRNeWDeeMAHjHozdrtZZ8qyeVD6Qmd2IK1EIgUkzpnNc5DoS5lNLDrqKRzUbD
8vj5TwhFiUUzpD1bjSEYK4d88vjt+2Yef/4Nv33CFv7d976SfOWOW553T9K6Kk9U0qDgPGqOFwHZeYgIkqa0MyznHBA+oHNEnfOI
1G0BKWsJmPL9tgV7/HQZ1KWKqJBoEipknxio9X7mJc99/n3O7XckzhkBADCYBa1NH/hMv5veIb6h0TYfBYAAvhzgsrCs18ILKGQo
vYlldHiAvffc28+/rBAF48pTEysnq8dZS1N6eieb9nWVrGftx/994piX+GTjm3zvB9+/8I6Du57TrKstjC93yO3d//L1URW8ltQf
ZdyBQgzyKs+NHs4XgAmIiUVEFDfHOGTKdA4J8V1bAQKkebJ/bX3so9de9tDW9cnZUd1nMTinBMBXf+XJrDLFHdXm5LuroZFLyDGO
kNRNAAAgAElEQVQKQU1c9U17MSjXhiMifkUgSxNWrxkv/fyNuX2wiuDbXH7LhXJkK4IJphzckUJMJZWC3kvvOdD4uTe87U+O+d7/
9uv/UttxYPcvN7Kw0ZtCgg3kNrIrLw/n+lGwkCvxyPMFtoN27sQ8X4BnPrsvGhWtAElC8B4bCAM+/dTavpGv/OHTX7ccPTvjOKcE
AMDjrrjM14x5f9Ka+r7RQk0IJUdAHEhzme1H2f+LCCOjI+zYvh1f5BhjSyGxIM1omZWAdqF7mXNxFuUhOKrJjM9umm407v/6j/zr
vb76P777Qb63886HTUnruYi3aCRQCGXoRLLMhZdOHfOU4qFMECJEIdCOXShEYvh2kqpVdm8cX/fHj7z86jPPsLpMOOcEwO8+/lJW
jQ5NjNYrf1LLZ6eNKipJtNarny/GsUAAtEt5B5R7du8mL4rIDWcENcKRNAN6jAPmqa0OQzvyTNv6w7GucKJjwQXnExVgzp5hRG39
gkOT4SUf/rN/yo58Nl/55n/Yn7Qmrp/OtNehIpKUtgRTBueX6bR6mgemFLLl+dxPM/e3SL599GOhh+BYh8r85xULZUy/Snm/0NZk
EoIk0XDrAsaR9/X0vHlw/fB3X/+0l57cYLoP4JwTAAC/9DOPC+to/el6W3w6CUVQk2CThFpzFut8nKRiMCYG8iwIKyHHEtIaQRJ8
ue+PsehlrYATzFGjcZsQRPAlGZCUdgdbJrQcs7DAyRwhxsc7q2VEWwYhznUjLaxXY9j4bJf0XHXDb39g7pn88pf+rxT5zCNnTOOm
6YozIRXUKxJMbLMIIWm7NU/zaD8GUVRCJBARnauJGMpwvXkexyMOKQXR8Y4jvoNaRC2iCaKWRF1p90vRpIoGg4REh4vq17YObvzg
jc/++ftUtt+JsPx+q2XA89cLz33fPzQP7W2+s9c0ntywySg+4DXFBoM9rh5/+jp+ECjs3DiNg9RKuQDGQpony6xzXAjMe9Xbv4sS
yJkgrupHcmZf8e3vTf8XcAjgn++5dXB/xf3vImmuwfh758/JUpgAFCTMnceknRwvsyABI4oNnbOiiEr5bh2eHBMsKQ2qvrl3yKS/
8YitF0/+/KpHdejuKxPLvWNdVjzr/f/Uc+vOiS/+eCq9pjltDM4S2WQ6s9FVIa7KRjCEqJ3nBeyfhEYRZ5gcXmRkKREVbIdPE4xp
zowW+qoL+9e+r+cZf8d3WpMv2F3teStOexZ6QZb6/vHSIQbzKEjewk8cjG7GUNYU61T/FWyAYBxqAlYN6UTQ1bPVf9g8uOZpX37j
pxsdufEKxjmpAbTxpKsvnW19+T9ftnf/vj9xrvdyR5+o0bl6c52A9dEYHYtaCKZQCgcaa2dyWMz6EkM0xGCn0ILQV282zCuTzf7L
Fdci1YOvNBrqwSZH5PkvIUr3GyhWSnerLcA0wMadu2hpqe8ILMH2gLgo6ENKEmp7+wY2vOulv/q65pff+OkO3Xfl4pwWAM+7eJU+
5FW/f7PZN/v7SWvgHQE/YGmJdMjfJcQVqPROxQnvFdsssD4SbBRWO+ZtEwETAolJcM1UvDQu2K//+clVTLDOTFxQ9yqtMtS2E2hz
CMS2RHtHMAWhVpCEklFIOlny25FwCGUGa5RKsy+kfZVP9mTZFy8efsBZ5d9YKpzTAgDgKQ+/Ut/5ro98sjWx+wJ1u1+T5CEzHVoB
VaBlw9zuXBEkSent66daqdByRbSyd2xjplhj8E2oeaind9v7r7vjgVesmeKSUKXlCypmH4YOJb8p2BAZjaPxM5AklrGBQTIEQsAl
nQs3UDF4qRCkDwkJFbdh/1Dtkk+QnFdctNhc5rMU57wAeMMN1/CLr/6T5ic/+5U/I4SfT03l/M7NPyXVOPjbFBWBgPgWLoAkQnpY
PPtSI24BlIyqeDba23nhg3LGK3v53l7Hrio05GSoM08T0i7cCkEiZ59NEjRt4TVu/zO/NNyCx0IisyQJNBuZG+8f+MJwf/U/HrTh
Zzt3wxWOc14AAHzozTfxgGv+x9079k18sZmYF3uxxoiiIUaLKQv5ZMJpL9AGJfNR/fcihLJWoZqAUw/GxpDb014CBVETi4WIglaQ
kGAk0mQHBC8BH4RUd/O0qwPXDO4lmdpDM0k5UCiiPQSxc4EyRudDo09Yu/RkWqhlrkX5FCsIlRwqxqDe442dj2E4zWcQbTjth2gQ
tXM3d+pxeUWTyrpbkt7RNw4NrGktpj9nO7oCoMQ1D95UfPaLP3yXZ+AB5P7hxhoTbQExSEXJCAKG/LSNVILg20krOu//NyqIJISQ
zPnGTwdGE9JQJ892USQO3BBp3ouRfRhpgdZoYenFcdmG7/C0R3+fOjvBO9bXGuyeGucnkjKTQWEEq5A5JVEF8XiJ9QsXt0cJZVvL
sAWUIKXvxRjaef+nhbkKSwWYZjwPVSILlKBagPFoMZT3VS/6QH/1wrs29f/cIvpy9uOcDAQ6Gt77rpdz3taLf+Bd4w9rFXKf5wgZ
omkMIsFjymSSE0WjHetoT5w5zoASbUaCuZ+nGWijAs4oSooNFYwGxB5EkwlcMou3SgVhkO0887H7WNMzA6GCJgW1UGVdZZqKn8b4
AmuUIEowsbaiF+YClxZ9sCA4MD6AuW3RonnF2kJbk3ggRFaAHMSB66WWjt09MrTq0+tGL14p2Q3Lhq4AWIDR1WvJkpkv5c1936xm
xmlh0FApQ0odSJOVHAyvEsjTJkEz0qJOxTusTBLsDLkBJ5aqm+JhW3/CtVvvoB4OgYAzhqzoZX3SYjzx9PgWSSgQAkHak1+WZAvQ
SaiEWDMRgVCPq78akAJMK9oc3Cq3afxB/7p5fOueMXvFcjd52dEVAAvwuT99JedvGtnfU5UXpuJ+HHX1uIqAI2bWrdxFQ8VTpNMA
pL4S7Q0oQWuo7yP1CauzbTz7sfvYkM1gihlIJ3GaYv00Q3nKxkrKYGiR5Q1siBxAQc4sr+HpQwFfhv9WEa2U7M3lOwvVMFA//0tj
Q+e9qS8ZP2cSfo6HrgA4Al//wh/Q35v90BUzHzGSF4gr+eNkxT8slYA3TSCQBI2pzqGK+hGSVoV+t49HPWA3l5+3gyRXRBMwBca0
SKUgKRLWoKw1So8ryErzZ0SHaxosFWLBMuaHtkc1EFxNjY7uHhva9Dup7bujKg9axkauHKz0Mb0seOJjr/ON1qGPqsz8REwjhu5h
0JB20EW3FIheAKsx+debAicV1NfoN4e4cOh7POfRUwyYyWgMkwy0rLQTKiA5Q67B+oplyIAt8mignDuWu3+nAkWlwGsLI1W0GMl7
Kpvflhetf1tTPbfi/Y+HrgA4Cn7/t57L8Ejf3cjsHwczOyEUoAmiVVbyIxM1JK4P6zNEmvh0FpeAtQW95vs8/ZGTXDx+G+Jmyast
irQAn2JaVQgZmrXIXItRgVXVKlU1WG0n70aNYiWLv4VQHEgLMQ4h1cyM39pb2/znq8bOP6ey/U6ElTualxnr1q9yaTV9jxH3ZSGE
6F9euuF/zMX0NKMQ47cMJtQwaksDXkGhHpEDPHDLJI976ARVcw+JOAo8wXrQKuL7QFwk/giBWpGzJjEMG6HiBTTW2BHxS2cF7JQ2
oeWQLg2CxoqqTyYH+0ffMjS4atf5/Td06MZnJ7oC4Bj4z795K5efv3m2VvAR6/ykWK+FmTltH/2ZgALORGOlqMH4XtKQ0Gfv4ilX
Fqyv3AnqsHjqBVR8AibgKwfBNrB5Ajal4gvWtaa5nzoGXQASCqN4k69oI2i008QhHTkHrAZXp56s/l5vJfurdaMXruTGLwu6AuA4
2Lp5M/0DPZ83Vv9Avc+tyVasH2yeS6cgTzzNrIlxAwyzi2vvdzdXX7EHceVWhhiIE1dLJUgkzYo04gYCVDWwqmIYlIJayLFYnKac
RIW9ZYO0jX/R7aeiCYmumlk1fOGfb938oMaoPGy5m7jisHLf5grAu9/2PLZu3dSyxn/IBH+HcXZuF6ydSpldDFQwqrTSWWbMAIaC
9XIHz3v8bkZqP0SMATlObUQBNRaMQVxOX5hhU83TX0yReiFQX9ECANrBRDlCC/G1vGbXvG318CUfGzQbu6v/UbCy3+YKwN9+9JWM
DPbeXTH6YVP4vM2vB2Xu/koSBCoYjcUtQ+inziRPvmqCh6y+i1qrAUlOu/bB0b+vOFdmAmqg5pqslgabq0KtVZD6FFmhXpD4Ltr/
F9RoQhL6b6lno+91wR9Mu6v/UdEVACeBa6+6yPdU5aOpNH8kEllmI4XXyllU2iJJgsW6OlU/zfmje/mZR+2hnwLrelDbOMEeXknK
UH9BEK/0uxbrrWecgh7nVviAiQkG6jOsG8370jV/OtK/6p4LB25c7oatWKzs97lC8P63/xIV07rbmNbvoeGAquK9J0mSMtJshUAE
VaFSeFbZO3nqI7ezcdVupOUgDEWijeMaMRWjPlr9JQMMWeEYo8XG1DOYT2PDCvaiiaLiVcKAGr/uHwZ7zvvUqsGu4e946AqAk8QF
569VydJPq+gtSWKxxuKcK+m29YwYB+fZ8sqzwyqXaJlUE6i7Jpeu/QGPueZWEn8I0gw1s0hYmIFzb8S/xHzlIBlIBQLUfYu1iWeV
KbBtLkNgYRn1Tndf5/7NPwddQN0+V7VYPIS+fdVk7f+tZkO71/X+TIdbdnajKwBOEn/zyTeyes2q2Z5a9UO+1WgaBMSgRlHjYyJK
x+hEF0JQbMx5N3m0/Psk7v2lhdiC4eoubnjUAVZl20i0wAVDyCYQrQHHMQLCHHV3m7BEjEFcYICCdWmgxzvSAKIWxc7RmphYd+AM
9L9Nmhqff8z891Guiaj1Fa2lQ39f76l//fLNv9zx1pzt6AqAU8B11z5U+zj4qYHEfZ3cqUhGYT3O5ATj54knOoC5UpYieJMSbI6x
h8iCJ2mlWCIRSJVD/NSVN/OYB9xN/7THNutIMgWiiLMnoanE4psJOYIHSRFJqReOLdZxXijoazrwGZ4MgyfTWax6Qpl33zkoaooy
dTglYAk24E2BN16DVqi7ja0tIw/46wvXPuScJvo4WXQFwCngHW98KlvPWzfpfeM9ifHNUBRYzebyzjsZJNMuqyG4cp+eEPwgRagS
qpOEZBqbD7Cx5yc886cHqZo9YHMwDjXtwmUtTiwB5mvrSfmfNptBpsq6mjBITiU4RAyOjEKyyPGnnaTzagsWM7eLUYn9Mibm/5tQ
04Gezd9ZO3bev63rv1+nGnKfQlcAnCJe+rKbWLtu7PPWtr6RGDSq35VIxXU8F9sSIVa/bSJq8TpIkWTk6Qx5aNCrjmdcMcVFw3dT
SXMwgZCEcnISucdPc4IKYNUzJk3Wpzm9bhbrHV4qFFIjYEgo6GwF0TLQRwXEI23qL59gQ42E/lt76uO/Wq+O3iNyQQfbcd9BVwCc
Ip5w3Toeef3VBwcHK283OrvXBsVqiqqgprPVM0UthApGGhgNKJYiaRKoUdOUrWvu5BkPm2WwuAPjlWAjCaeGFAmmrPN3+jDq6fc5
m2rCmDSo+QLU4KkANvIHLk1XjwnVNmuyj4xHQUipK/mAH+7b9GEyvtlrr19BwRkrG10BcBp4wU3PYqC/9jf1SvExa1rB5w4jCS6E
jm2Bo73boFpDpMCqB2ngOUQa6vQX+3j69Xezru+H2DATC3BoFSXBhBr4GpAuon2RrizxnqHQYmNF6XfTZOqiXQLDvIGuU4iUYfNh
WCAhUfK69iRrv71lzYP/7tK1j+m6/U4BXQFwGrhog/Abv/7Col5z709kZoc1ToOCSNrB8R99+N460AwDJBRkQD3cwxUbf8zjLr+L
LNkRvRPaS9AMoz4KC6RMlDv9bEMh8oNVnGNNkrPazFIrZjDBg1hc6PzCq6UBQEo3aEIV36pPDNTW/EZPdfTmqnRpvk4FXQFwmnjm
Yy9k7ZqR7wc/88bE+iYqqJ68FfyYnzpGYJEgqDh8cojgB7A+JfEG26ox2n8LN96wh/XpHWBbeFMhlx5UAkamEJkG2ySkzflAoHmO
0pNur6oBKpgAQxRsqCn9zGJdK7oLk+zkWYNOURORBSdSahoCBJcw1Lvme/29g/+xOnvSqV20i64AWAx+9jk3hLHx8U+hzf9Q9SqS
RSZdCQu46eNgbTPhLg4BQ47VjEAFFaUPz+Ou8Dxk6zYSP1UWII1ZfkKBSDTMqTiCLN5IGSQBNWRFYDyFNVWo0USCIwSDaIoJBqML
agqUnVddbJyAlqXDLKggJJpI3/aR4dX/Z/OGC8+5wp5Lga4AWARe8guPYKQ/HOrJWn+Yan5IXYKzgjMeLY1URmMhEZ0rMHL6MGpI
8hSrOc1gcMkBtox8h2dd2mK4OEjIonswCS0yPYilBWqBFDTFLpbZUxSRHEKAQulretZbz2g4RN0348QPbSp1g2h7tSYGL5UTd3FQ
hAwNFcT1+Gqy+j2pHfrHftncNfydBroCYJF4za+/lPUb1n0uMfkHU9PwJghGE0STuUE/pxYv0kmu4glpg1mpYpImI26aJz5iG+dd
sAMQohOi7cNv33W+5oCcqt597wbEbEBjwBiSAOPBsjmpUXc5JB5n2gVElCAQREq1/ZR3HUdrAKjiQwNDGhLGv755/YP+duP4g0Mi
ly6ub+cougJgkXjy9Vu58qrLWwMD9r2JTuyyGrDBItjIuluGx8pcgO3pIzL+GGaYoULOQ1ffzdOu3oNJfhQnWpF1NF1XUCTERdxb
MEEZbCjna8YoCjRitV/j8aZdSCSmF0q5JVhsC+KTdeCreyvJqtf01Ea/M5I9Ygl6d26iKwCWAO94w7NZPVa7rV5p/UUavE/UIN6g
RC2gHWG/2EwB0RTVQWxlmuFsN8951C42pPtIRSm0AK10OClJI8W2CIWNVUIkd4wGZV0KPTqLkby0N4TIS7CATtws8hlEL4TFhixU
TN8XhwZH/n1L37ld2mux6AqAJcJvvvpFrprouzPx31LfVKEdFGTmLPtyWPbeaUAFyTP6wwwPv/QHXPvAvWQ+YGcHSYzhuGQfSwZT
6vHtPnls0WB1oqyhoOpbJFqWUBNbFgIttYfFagAq2FDBuqHWSP/mz21a/aBucY9FoisAlghPum4royPr7iC03ppIs2lMgeIiOWX7
Q4sc/yJK5qc5v7qPZ/303fRku4CAdXVsSCEpOkxaasAIRoXEayQWTHysJ+Bz7m8tA8FT9Y5MAR9K3sGlGWaCYEM99GWb/27L+IP+
ZbC2bkmuey6jKwCWEDf90o309aVfEGn+R9CmBlzpDlwaCEpvsp/HXLaby9ZMIOkUPmsCDcQLPokCp1PQsnKxBCEJBkQpMo+rROLQ
jd6wOs2oBY2aSZA5m4SWXAWLur8CLts71LfxLUnSt7dPrlqCXp3b6AqAJcQL/tulPOyqyw711e3brLT2IK40/bVXwRMZ6BRwBBPw
Er0HJoChANMADWwZ/jFPuX6Kum+BeIJtgTkE0oqGwA5H47cFjIQyN9EKai0SArW8YItJGNBAEI+zcdVOvZAELTkTTiCg1JaWghDt
CFASkRqEbHqgb/V7Vw2PfH1db5fffynQFQBLjDe94UWsGuv5QmaKjyQ2+EBMyAknIQCE6Gf3RnGmShCDCQbrmhgzQSK7+dmH38qm
od2YpMA0IXUaWXCMJ/Gdf51x+68gMein6lLSIgYmG4QLGrNssg6XtphOPBIMPblQ8SVpynEegSBQUo8Ho3hb4E0AkyGhrlU7+u9Z
NvrmseEtRcc7eo6gKwCWGJvHhZ//2ae73p7a+/GNXQlFGRBkYjbfcTgEFUVFSVyN1CuCRBWbPqqtGlfd74dcf2WNTA5hcBixJQmJ
QU0osxE7B1nwL/IEtLkCTDwXxWiL8cyyLgh9eQHiaSaQGzsXHHS8/iOOyG2WxM9LjmgA198a6jvvY6vHtsz0yRM72s9zCV0B0AH8
6vMfxdDI4G1Wir+w2vCJFmV5rey4kXAq4MWQuoyayxECs0bwpsqYmeIXrt/J6v6dVO0MuBZCimoFSAkC3vjlrVwkAbEFo0G5SC3r
c4elxUwl0EwMJqQnCEZSkNKwrykgGFF8rqGervniQP3Cv1k73CX6WEp0BUCH8OuveonbuHbk3Smz3zLaVAgnUVTDolrDUpBqCyQn
aEYik1x32XauP28PVbeTVA/FVVENaEaQhGAUNcvLUNxmHa7nTc5zyibvqPkm3nqcEaBkTjrOFTAOCDHrL1gkpGRmcG9vdeQtvdWx
vX3Srey7lOgKgA7hWY89j4He7I7BXvvW1LaaUODVH38PrAYJFdTOoMaRaEE95Kztu4Wn/fQ2BvUAaXCIFhiJE6Xk6kFCsiLKFgZV
xOf0FC02Ghh2DSq+FalIT4pCXVAT4lYgJJAPhYHaps8PDgx/44LhZ3W49eceugKgg/i1V/4KAwO1zxtafx+0kZuUE1rBjSqFLchN
ggkwym08+cq7uHTj7THWP9Rigo+Uxj/xiCo2GBJnzgg9+XHbT7tOccFoImyylqFGg4pr4dWdqPeopiAF2FlEM011w7axgQf80UVr
HtEN+ukAugKgg3jyI7dw3XXXTGXV7BXGhjtdaJ1gEQyINCnE0jA1TKhwwcjtPOORh6i5gxAUQg3VSmQHMg5MZO+VYJFlLt0lgKgg
RkAcFXFsSFPWB0PNO4JxHF9CGXzIUArEzGIlaVXTsTfXq6PfqNluaa9OoCsAOoy3/q9fYNOWLdvTJHw2MS3fLmAXQkCkbRKLWW5C
wAalIKEwnv60wXOfVGFL7U4qeQ+a+bKs73x+AcStgKgpU3+X0Q6gBoJBjYlkJEXOWDBstCk93qEm5hEYVZLgsSEgSskTUOZLiAdV
TKhoKgP/NTI89unxblnvjqErAM4AXv6i57nRXj6QuYmdIQSCEiv1ltG0RturpwFXxXilKrt5yAW38uj7/Zj+1iEIhqLSJNgpII+T
PURLOVKgJi8NaMuMYGLIno1BTNXZnE2kDKMYihjbgJIFRxYcRmOhkyAgpoVJp7BaxTbOa43XL3v/xRsfvHeoS/PVMXQFwBnAsx67
gTXj/bcnafgIkudIwBgbQ+XFzmUMBoEi9WS+YL3dzzOetI16NgGSQXKQJJS5de3ine0M+yg9liLhfkmgCMEIGI+IoyIFG6opI3kT
ow4vkFtDbgVvoi1D8IgGVAsk9OeWsQ+ODG7+VF1WrQDT5n0XXQFwhvDGN/y637B+7TtFm1+x1qvXAg94UkIsroUXpZXk9KnyhMt2
85BNPyCR/WAt2ALjzYotzz2PyIHgRQk2oKZFqg3WScH56qiFHG+Epk1o2YQgkbosCRprHvhUkzB8cz0b++3e+rqJTC5f7g7dp9EV
AGcIj7x8DQ+/7rpdA/3JH/pisgE5KkIQQxCDiGAIVIxnPNvGM39qJ2M6QSINXJqjYhBXL/f5KxUmhiZIrBjojaJWEW0y6Ga5wCiD
oUUSHE4suU3wErD4SBYSMhI/5Gvp6F+MDK/ftbH/ccvdofs8ugLgDOJpT30cG9cN/31vNXzBajMkRpkzf/mCJBQM5Lt4yvW7uHDV
DtKWQXwaiTC1gmqdFaHjHwMKMVsQsCGmDUu5PUm8Y1QCWxJHbz6LUcFrNPwZDTGk2fcEU4x/bd3YxX93+cbHdFX/M4CuADiDeNQl
NR513UOm6pm8Hj+7w2gBwWM1kEmgpoe4au12nvm4HWQ6Bd6D68W0yTyXO9T3RBAlmGjZT7zBegvYUmYpmTrOM4E1QanmgVQtVsuM
R00J2rvTyOiv9tVGb8nMJcvcmXMDXQFwhvF/XvlM6tXsR1liPibqvCEg3mFx9CWT3PiYKcYrt2HT/5+9N4+37CrrvL/PWmvvc86d
6tY8pIZUSACRwU4LAuLQats2io2g0N0MKq2IKDaoSLe29qv2aw8qgsxtq0gjYNMMDdgQkCQEQsAkQhICpEIqlUpNdx7PtPda6+k/
1j733gx1b02nqlJ1f/ez7r116p6999pnr2c9w+95nkXIJIXEQgYS8Pkceg5Ke/cLqWZhQFEkKOINxOTkDNYiwDZfclU9ZygoWRTE
BxwWJQuSNT6QDQx/7epNL7/QU7lssC4ALgD++I/+cxhsDL4jM/W/V+NVMsiKDs94fIvvfPxRhjQCZWo0YqvS3loRf85RgRFFlhKT
DInAc9Ylu6VX/DRURzVVEpQs9UXIQ2A7sNsI9W6Bmoy2EY2aPTg6uPWDV+5/8sUr4S5BrAuAC4AfeeZ2rtzw1AfENP44ZEW7pMWe
wTFe9n3HGK0fx4Q2NjqwAbUBtSVCxIVUV1/P+GtlfwJdEiZGY4rda6+775kNUSULDsGCVXARjMeg6deYQpabfIsnhHl2+DalyZgf
GOx2XeMPacptTxl+xXn+NC5vrAuAC4SXvuSFDG2RT0uQW4Z1TL//u+7iyfvGEVrVYpXlRUtMP7XaSc90VPUJo0m2ejQetQFvI+oi
aqv8AvwZDVkxkDREVrxGRKPB0mFbXdmVRUaKeR0oN36xVtvzwW97wrPWGX/nGesC4ALh535uF89++rULO4y+7ckbHpx98Q+Msckc
wkWqzjp9GDFHosUEm3LzY1bZ6ELEoNKLSfRrZKDDiBqGtMverMPuknZ9wr5928ATJvYP//R5/ATWAYm1sY4LhFe+7AXsnfjIZ77/
2uyufXH+e2WqSzDZKabNngsY0Igt7FLJ7p620BeIAXIIA0jZZGtu2dPeeWymnd/w1B/43n6ddR2rYF0AXEB8n7+ZkatntuvknXuK
r0YMAW+Kc9BEdDUs9yhQiRhnGNgwjGSWqJxVC/FTObWaiPObQCM0h/mHj80M3H3f+Kanbdk+3Z+TrmM1rAuAC4jj1/+FrY0dfgUz
Y3uzHfsxG3LqeRvooylcMQmlqrpLFKxvgLGJkx9N36hGUQI+tDEMoMVVHLxbOfAFv32sqT/7n97wm7/D+elsso4VWPcBXCDMX/8W
ShZ+cEssfnr7wqBtH5lITr9eemxfxjKNuKfqRxUH2UUAACAASURBVEkJfN5Caava/X0aouBMnUDB4vwuvvh3Q4TFK2wo4kvGp4/t
v+FdH75gn8flinUBcAGgk9+kc/cdG4rJg7+eF4u7XGxQLjYpptpVQ1HAKNGkNF815dLCTKW19QxHaluuElDxqAlEE4jGVw09q+Nz
pkOrSEVE8dXoRTJS2FFECb7GnbcXHDu8BRNHyTXuak9MP+9jb/7LiznR4ZLEugC4AGhe/38ymVv890Mzc9+rRmU2W8CEHHu/wTVr
ZJojMabiGOJBAoawXDdAznBQ0XM0VD9TCTIbDTamLl+pMYc7i1FPP3uCCodqjpIy/1RhYWI3d9wSoBxGNJL5wg0U4de7k+1//t+e
+/oL+tlcblgXAOcZevAWDh+4e9v0icM/nqmvmdiz9w3tZsH85AISMyQaTM9eP2deQVnxfbW/OcOhkDgBWrEXK21GPEgJCLGzizv+
forZyYhgiFpirAjR7Jxb7PzCnXfcWT9Hk13HKWBdAJxnzNx6Q1Z2Ft+Qa/NxGR4JAYmKkRSHX5hq0p3t4GIN9YLEVCykx+K7qCER
pEuSBBnJxxxJQiFAGODYfZu569YO0Q9XmYKeGAOoFcie3tXuC17/Az+7/lyeJ6zf6PMI/dpHmLv/ru/IWxMvrIWF3FDgTIaJJtnI
BugY5seaaGFxZJiUYI9KctjpeeMInCGkV/jTJIcmISkIOki3uZGbPjVNe24HosMoEeuSfeJsjgS2y2LxB8cPHHqcfnXmAk/k8sC6
ADiPmPvyDbUweeTna63x7RKayTCPQiY5hOQus97hFwLduQIba8tOQS54xe/TQGVqSCBqCVojFlu57+vCsUN1tNiEaA1VJYaIqENJ
3IR6Ibu1Vf7Mq1/60+sOwfOAdQFwntD8uzdlcwszv5ItTr9wNPPWSCBgQB1WDUJEJJLHGnQMCxOLxIKlvnsqjxEBoFUNABSVEmMg
xiEWprbw5RsX8d0NoDn0shHVpQYgCkZKMsVqN/z0/PziD77tVb9/gSdz6WNdAJwH6PGv4hfmn1Icuee1w7GziaKDWEsQg1I1wUQR
iZhocVqnaJY0ZxdTme1eu42LXPtf5vsbIIIUKJ5Q1vjGV5tMHBlFtEbFQFj+e7LqtRIThQy3q9tq/dpXvvz3QxdsKpcJ1gXAecCB
j/+ljH/lC98zsnBiWx7L5PSruuqmGHlFgItCjAGrAt4wP9FCOwYbky8g/d3FqweoQoyKEojqQRSNltbcKLd+fopQjFRCzKcqwOhy
h2FNJKQoio2Iafvvbk3M/dCvPPvFF3palzTWBUCfocfuojk1s707feJfbijnLQJGMlzMsGrAFATrUUzK2LMRJZCFOizktI57bDGA
8QaJgb7ShM8BVNPOj0QINWLnCr782S7zUzsx1BCNGJM4DqIe0RQFSTAUkhqGDHTMAIvh33Y6fuf83RMXdE6XMtYFQJ8x8ZmPZAOt
9m+OlP5an9clVDHzXlX/3o6evvfy/au/iYb56UW6Cx2M5jh1yEX8kYmAsYKqQ7UkFps4/I0r+MqX5rCSIboBWUo/6c24em/1WwSI
SkMykW747tmJqV/67X/7+nWHYJ9w8T5NlwDibe+nO3f4O+rj971wY9nJO9Ghsvot117HLwRRQyxgbmIe47MqKnA+rvzMoAohBERK
rLX41hV86bMGuvtRNQRvUV19/uIMQSPESKMkY6Hz0vnxyavu+OjN52kWlxfWBUAfcegLNw02H7jntRtldruNbTJqrOXJU5RoADWI
Wkx0dOcDnakOxue9fF1UFdWLTxoYI0SZR+MQ37xDOHE4I5TDCA2M61YVhx4dCqAR4xL5KVdDvau7549P/Jt3/OGfZOdrDpcT1gVA
nzD2P/+T6PFjP7qxOfN8YdGGmpJ7MGvQ+dJ/C4LFqCOjhvGW+fFFtJs0YdWYbO3+lu84AwgxKsY4FiY3cdsX5iiKiDECMQczXxGF
TvbuFECMqkSbCEKNaG3u9ZUzxyZ+9E9+/rfP20wuF6wLgD5Ax7+MtZ2n593Z3x/w7UbE4MVUdfFWX7A9+SAKJhqMt+Sxhl8IdKba
qZmmKiKm0gL6P59ThyI4fGsfX7lZmDiWI9KrEizV7n/yC04NRVISUddCaQSJkLfiaJhp/vI3b/nK8N1/c+P5mcplgnUB0AeE276Y
LR648xWme+Jqb71IrGGDo3AePWUjvsrdiwbxllwazE/O02kXGJM+NpGeG1Grqr7V6BtOUm406e5psUudsYNXcscXLeqH0JhX7+1C
rLPqI6cpI7EnAAqT/CADMZNGl2c1J2d++IN/9dd9nN/lh3UBcI7R/Pqnuf/mL+0wJ459f4OOCaYEqNpgn/rtVlL+vpgqSuAhdgyL
JzqYboaJghhNvQKqHbb/jUOr3byXn4CvZE4GRKK0KJob+fKNC7RndyBsqIg/AUyRzIA1nICpr2DKXY5G8UYJGmlI3igW2q/+2p13
b33tD7y0z/O8fLAuAM4hdPoWpu744hYzWP+jkYGh/a4dsVrSzTqUJpJ1U5rvySFVGzAFU6JSEKVIggCD8Rk6nhGnHS7U0FgSTQc1
KbhoouszWTBWab0GsKleAVrt8oIQOHLPMIe+tUgIdTQMp/fYxRVJQieHCnixiBpqHmxUChMpckOXKHVbf7Z047+ePjG+/tyeI6zf
yHOI+b//PHMPfvO53akjP66G3AyPUpJRalWTXxI7bjX0susf+Y+0xGJpmBtfQEuDJa9qBqSUW620jf6h56AoSZqATaQfM48xg3Tm
93LbLeOUnTqoIBJQ6abrU0tKD17bCbqyyoCxKSyoCsZQv+qKPa/YuXnrtpv+7KP9nOhlg3UBcI6g3/o8Uw8e2dKYefCn67NHanZ+
EmoNssGNBMmIRsGuvQuuDsFoRmch0pkpsb6ODTmiJpUMw/c5JlD5JSqmn2qWhJpdJJQjfOO2EY4erEEYJc9zlDZiCpKfwIFmp1XU
QFXx3mOtoeZyrtyxj9bxqWvuuf2uF73/v7/HTd9+qF8TvWywzrA6R3jRU3eY5tFDLx+dPvhzG7WT4QNF6alt2ICxBi06VY6crRyB
FRMuKmW7RH3KD0B0lU0yZc9FjfjoaQw3MA4wsaq6E0kL9ORyPe2supyMZ8E16qgTIrqUfbgqTFnZ8jWEghhhYXwPn/1opDm9HQ2N
lOZryyQsMKB10ByRsooM9LoIBtq+mzoVScSIJcaIGEGjYq1FnLB3zz6mJydpz807l+fXTrXmDhwbO/HN6++65bQ+p3U8FOsawDmA
3n8DW3L5zrw5/YZh36rVYokzEUugNT1L3dXJB4YpjVkq6KGqaIynpRAIyZno1FEsBppTXYxvYLxDVFCzmvA4F+hVFQQkpNLioYGW
e7jtC7OMPzhE9CMIOSKpwSlVyjNqUhhwDRMoaACXSojbPJ3rcXsex8TEBIuLTWzIxBRsy7v6y8e/cXD4ng9c388JX/JYFwDnAPO3
XJ+3Dn3j5ze0TuyxEYkiRBOwlGRll3J6FpcPYodGiZrIMiJVg87TgibHW1BMMMyPL1IsRIw0iNEQ+6v/sxz2S7oMUiJxI+OHtvKV
L7cxbCA9UqGK+ZuU+6959d6CtZKZrDXEyubHwVVXXcXY+BiLzUWCRoJ1ZGRS68ZnTR85+hMf/usPrD/DZ4H1m3eWmPv0ezhx5Ng/
ipOHf2ykO2WicRQmS2mtFNRDiS1K2jOLSH2Y+sAgvYVk1sgLeAQUJHqcERwOLYTp8TmIDpF8uW7Aw8P0vVD9WXsIemHAlL+v4inb
Q3z5cwv4xT1oVKBb+Qg8icewQgCY4mEagC797P3mfViy+ffu2MfY+BgL7QUiEbGWwllCjAyqa5hW8R8P3nvfNde/82/Ocl6XL9YF
wFlAH7yBeOzezRw/8uuD3YVtYmLKdBdDlF4hz6rPb/AsTk9jBmrUh0eIYlBjUTEr9sS1Un2T5mARpATnDX6+S2eqSUaGlUrVfjhX
hyrH4KwziQwxpt6F0XTR6Dh0IOPg1x3EAcSWiPjKDDErqgP17BJN/IGeQJJ0uVEqjUgFZxxiDLv37GFyaoLFhYXEiIyGGCIh+ooo
7SQPbt/c2Mwr3vvmP3d6qHWWc7s8sS4AzgKTt99GMfHAj25bHPuxkbJjFrMGahRDRNTgJaNwjuCEzHgaocPC3AzaqOEGhwk4ojpU
k98uriUAekIlKHl0NHxGreNoTzTRtmJKU7X2MiQxYel9xCkMeZa1BNQkBx8FmC6thR3cekNO2dxB1A4iqa050ULsefx77cZTPkBK
FZZ0PTYSCJhcCEaxWcr3WWnzo8kZKAhWoRE9IkpHQWNmpSsvU88Pf/g9//Ps5naZYl0AnCH0/htoHj2yZfroAz8t2qp5Ai6aZSf+
w0rmC6nopQZPe24eW6tRHxhIPXVikgDLqvoq512xrSsGwdGcK2jNlJg4ACYSJRCX7PCIqGKiYFclIZ3CnElxedU22t3FVz5X5/C3
wGUpnKBhsNr1V05+JeRhP8Eak3oUwiNs/pTzIA97d1wyGEQMNsiO7mLrV2/6zPXDemC9kvDpYl0AnAHU38f8lz5n/PHDP7WhM/9s
caWUAg3vVs/2kxRgi76kPTuLreXUBxqkj0EQY07Bi69LBUITtTjH6gBzJ7rEZpZCeBLAeOJSVyFwkSUBdeaIKIs422DmyD6++vkG
hFG8LzBmENXT6zWrKD54jLHkLmffrofa/L2ch0e9EknuhBpO/FzrWWOHjv7we9/5P85mcpcl1gXAGUAnj8qs+Bfk8xO/taFcqJVa
oJkjD2ssMNVU/ZeIRk9zehrXGKA+MoyKWcoVWC2nR5MqQTSKihCjICHDNx2LY12st6mFmKFqz5XShkUNJp4l7UM84hbpLm7i9psc
izMbsa7n7BsAWazowascospiFAAFaxwisGfPbsYnxh9i82tUHi1SsoJFgVVDI9iGn27+yuc+9pkrDn/8trOb42WGdSLQGeDlT9rU
8A/c+8cj4w88bSB2pJsJiKXmIZp4crKbUFX/lTTUEDuekOUED1qUGCNLffxkzSYgibwDBoel6BbURoSsloFEApGq/Q5GTWIMmrhE
Njp9IlBKOnrg7p184VMZwQ+AnUXiMBJrSDZRRQhWeawkFQ3pSYCSwK4rdnN04jitVhOJvfZly1/Lb1WMJg0ompQzYELEihVj2NUu
O9z99btvuOXI1y/uwokXEdY1gNNE+eX34Q8dekb9+OHvGKQrhaMq7Q3BrJ7u22PhpQc5vVCWBX5+AeoNspFRekU1ECE+Sr6/IiSe
gRKNRyRiNWKDYAtYONZCujmUDsFWiyVVGVJzllEAzenM7eLWmzydxRGUTpIgmlX5AWsfX4wQY0wqjoH9V17J2PgJOu0OIfYE1snR
4zpFNLU2l1QzIAsui53wr+4/+sDjP/Ou9ZThU8W6ADgNaPsOFtoLT6y1Wn+wqbmwyYcOzcwRyTHR4G1YcwkIEVmq5gPiLN1OiZ+Z
I6s3GBgcSruecpKdOPkLKq8iUkUdTPTYoJRzge506ipkyJLBIUqoxqlR8XX5x0piQWxw+J4tPHDPAJATI+A3pWsybYgbEuvvJHUD
VJXgfXLeOce+vVcydmKMhdYiIab4/1r1DEzPfKgWP8bibEb0SiZuZ1l0Xv62N75pXbM9RawLgNNA+8PvZfamjz+n1hx/uosdIy45
vWxMFJwosvoCUxB1VYguCQOjEWcUgqc1OYmtN6gPb0DFEquFrrBkN8sjFudyfo0o2I5lcayFdoDQaye0pHesMUNNJJ7Ky6hYVC0q
bUIMzE9t5XOfXCAWm9AYyUwjcfx7EYdYJ0mm5UUvRqryZYBEjE3euz279zA2PkGz2UJC2sU16FoKQMWvkMrXElBROqHAOov1Ygda
9rmDc/nOv3zdH68x13XAugA4Zeg//C2zR0+MDE8ceklWjLt2HvECtRBwdFHCKSTSCEoi66S4tmK0xGpJpgU2eGZm5ikag+jQCEGF
KCZFD6SnHWu1nFnSFFRJKr4Imc8JC5HmVBMbLDY6TLRYNRhdq2iIAr5KLFIk1tCYYVwbjQ2+fD3MHN+CaI6RnqnSSu+JGVBWEYi4
NBSPcSAmIkaJBPZdtY9jY2N0Oh2MWCSCRSGJPMxJhiB4k8KMTsFp9R6bGJA5jo2dgWva0+2X3XbLrdnCV4+c5ad+6WNdAJwijnz1
czI1O/1jviy+K3MmraMqrFf9eop4aHy8t5h78GVBmJ9D6jXykRFEzJJPICiPXgl46ZAGyBDNWJhq4tsRFy0mQtql16pHYCEOpQIe
ZrFyFpb4osHEg0McuGuRGPIVJ1x55fLQX3v8ByOJ209l81+1n/HxcbqdDsHHyhfYc/ytYUD1pODD73s1FChFa0ODg687cu99/+K3
funXVj/eOtYFwKmg/Pz7sM3p78rnH/y9LBb1skyFN851aW5ByZyh7HYI0zPkjToDg4PJIdhL811L0ohDYoZvCwvjbYx3VRuyiEq5
egKSVsk7krQAlSYqbehcxe035TRnRzidwNGSzY/gnGPfnisZHxtnsblIjBGXuXNavyCiRGeEdrFlqJDfaB6buOrr77/xHJ7h0sO6
s+QU8PzdOB0/+NrN7aM/kqkaY6tkGI2ImFMI162EofLwpY3rYfUAei0zIVK22gyODCPW4cuy8gMs0wUfftpkguREVcRCUXYZGBrA
5RY1HjX6EKbiI8KAkii3qh7I0+KXGvffuZ9bPj2EL5J2sdq+IRY0xqV7ksg8wt69exmfHKPZaqbrVAEDIXraZZdoA1F6PRPPLKdZ
BQJKLYjkIe4IhvAPX73j+tvG7lkPC54E6xrAGihv/QANE5/WKBdfNBy7pipXjzEGa91pLv7V0XMMiiSyEBqYm5kl1BowOJS0AAzS
4wo87NyJNhNSwpDPcJ2MuaPzSJElqu6aCyuCNIl+ENERVKE5N8SXri8p5vcSQzrLatCoGGOWYviqyv79V3Ji7ATtdpuVpoLq6SdE
r47lLIgsOutb5YtnZucef+Pb1suHnQzrAmAV6NxdlDPHnpq1xt8yFFo7S7/M1usXepEBqTznZVHiFyqewPAIImvwBCQgqrhocT6n
mAs0p9sY8qot2SrXX9n8xuT4QsFv48A/NDh6fw3V1MV3zTCnrWz+Xpx/f7L5O5XNf4ab+ykhzTvxA0pjEHU7Y7N4xdv/yx85vXO9
weijYV0ArIKJj/21TH350z88vPDA0/OyZXw2Quyr1ZSYbkscARGssxTdLmFmjrwxsCpPIFF/U8FOEwUXMpzPmZtcpCxAyaqznPT0
xCg45zGZZ3Z8E3//WQtxkCDHMaaW/ASrxfnLZZv/yj1XMj5e2fwacc6dClfojCGAi5Eg0HGCIjbvxJcOBvvc9779Xf078WMY6wLg
JNA7PsGxb359dzl57MXDoWmteqLNlkp69RNLju1KE7ACEj2tyYk1eAI9lqBU8XIDavCtwOLEIlmZgRhUqvj+SgGiFrSGUMPHDsEP
cMctJQtTV6DRIraFqq2Ezsni/IqxyebfvXs3Y5NjNJvNRHuu3lfxl9JYqRCcI8GgyFK+hChk2G3zC4uv+8yNN2+48a2fPDcnuYSw
LgBOgmNfuiEfNPG3B4rO0yxGRASjnWSb9w3LMa0e6cdowGqJjQUmlmvyBFQsUQzeCd6lFWa8UIwXyIJBySgRtHLOpcIdlTdQLWId
wTeYPrKFr99uiH4Y1GJ0OO3+EleJ8yc/xP79K23+amYiaIwYreL6UgmAR/KazhiKUJrEd6j5lAHZjVHU1Z85O99+xac/dd260/th
WBcAj4LO370dP3v8O3X2xI9bjVlXBvFSw6oi57EZnzxiKN6fnCcQVRENCB4TS0xMOQeZZBSLnoXxxdRmXBVjumkFagZaA1Mido7o
A7F9Bbd9YYH5GUvqZ1jV96PiEZw0zq8Psfmjj4/qJH10HeocaFYPoyYISi4WU4a6dP2vjh08/IS7/ufnz/48lxDWJeKj4JVPqOfl
iW/9zsZy+tmiIqUZQIGMqsT1WZkBq4cB1yoLLtbhfQndgsbIMLkIZVEscQREqgIgpJHUbYM1jm63xA1mNAYVpVVVCRrG1QfRvIXa
OZxu58BXNvH56zwmbkerVOJ06cUK5k0yO2IIGDE459i7ey/jE+M0m00UxdlUwvzhRT2W9ZtHKQt+FmFA0p1dYUKlqIQVi8Y42G23
u3d/8+7rbzu+ni3Yw7oG8DDMf+hPaLc7zxjsTP/oYDFrrIKXnCCuemT7rAGsengFrdyQ0dOcmMDVajSGR0EMcYlL16PVJqFi1GBD
hilrzB1bJLYCElM9IUi1+AwWjRmzsxu45YY5YudqNAyn/P6lHP9YqfLLersxFhFhz549nJg48RCbX9FzGiY9VfQKpghgEZyPDEax
WRlfUvjimX/z+3923q/pYsW6AFgB/dL7aU4e3y7d9hvqsbvFKRitwnKrc+jOG4wGpKrJj0bmZ+bwtToyOJxKjotN9n21BSqx6kFg
IVp0MdKZjNiYbPpIGzUlvsiRYjdfuyUweWwA/GBq7Lnk9U9NR+LKOH+1uPfv38+xY8fodjpL15mKfF6YO9YTOVppK1YMLghZqdtm
Hjz+r2/55A31sc9+84Jc28WGdRNgBV7z1FGzcPgbPyPzE7/Y0CIzWBCHkYjVsOzH7qcJwGomwEozNxXg9CFiYkQHBnFZji998gUY
qtRaTcaASVRiCQHvoTE0ArVAyJrkwwPEuIXpE9v4uw8VtBc2YSRL3n2JVZMPQDNMFeeHZP/vv3I/Y2NjdLodYli9jNfy9ffJBFhx
63qxit4LlbtTrJgnTEyM33vk6NG7b7z31jM7zyWEdQ2ggn7zRiZbxZ763AOv2EAnL2WAlgwhCvXQxmlRMfF6cbczGI/85yOvY5XD
Ly+bh/MECvzsHK7WoD68kSgZAUs0QjBVlSJSEY4cR1isMT8uaHCI86gsouUQX725Q3PyapwZIJpJxJQpN4CKY6A5oYxLcf59e/dx
YuwEzVZzKc5/Srv+I/7kJDfoNMdKh6lW9zJIqh/YM/rrbR2uk71mfGpiz73XrZcPW9cAAC1vpzl9aMfiHV992+b5o99tisJa18CK
kMWAxVe7kiUV3T55yurqQ6q03RU7YYSiUxJDVexTdNXnHJYf7pU7nBIpWk0GRkYgs5S+JKAV+88uvTPaAutzfDtQG42UQx18bRMP
3ruNL31SaTZ3gO2CdFL34eiIUlZRBouxSfDs3beX4+NjtFrtJWLSWpqRqJB7wcRE2AXBE+iENtF4VH11h5OgO5uR/CUpamN0+XWL
Stf4nWUs7eF7D372c/d95bJ2CK5rAIAem5HJW276F7WxAz8SI5kYgwlNJLYoCLSxdNUQolaDMxpeFY8nEIjJnwekJiLBpHL6uiLl
9dFG7/97xFyjSUA5LXFasDg9iWQZDA7hcXhxYDKsOqxCVwoyjdhWZO5IG9fdRHN+Fzdcv0BzZg/k7VT5L45ABCMlBkeIguQRLFz1
uKs5NjZGt1tWxCIDJhGTpKo9eLJhklsOxRCMxRuDN0owETW9ykWc9YhSCcmeBiAQRCiMp25sFibnX3z04INPvPmdn7jAT9+FxenV
cb5EMfuBT2b1E8d+MOuSR5f11d2XxVAV5kiEFULq8BOLtOvVqmpBZwJFKDslWVjAjAyhjRH8wgISIw6LkOPKTeTesVgLzDdh4Mgo
003L8fsWycViQ7cSLKn+XlL9FRUlauCaffs5cewoZbuDxpD8Fitu12o7iorSzpRAJBqDN+AxqK+lBYtDxbF20tKZwURlKFp8qyTP
GjsWj8/+m//7tve+Xm8tvDw978s5L3Zc9gLgzje8nvs/e/tTr9KF51jbErWp8m3fIFUCjyoR0FLJOg4XUhnsTHsMvTM4NEJdDaGp
2NkWbstmjNRYbM6jgJUM181RbcNAgQvDTB/cwIEDXUaK7QiQqanyEdKuWWqk7hzRGfbs3cvM8TFsu8NghMzVCCE8jHyzCiqikpLu
QQyC95atjOI1oERE+2eVCpCZlCrdEm8s/KtrFof+bva9H/8ka/dluyRxWQuA8H8/xgd+7/8fze8/9EcDvr1jyHXJS7t6c4+zQBRo
O60qBwtScetzm5NnOSgUS7H804coWE0hwGCgc3yK4a1bkAKaCwuYqDS6SqhFsskupjHc5Qe/++DO4W311qcOXIHmeQOLaESNwRNR
Z/EoV+zbw/jYOKMdZZNpoIARg9qHXu1qd05UqfsCEwXEItFiTU6jMYQ1GUTQpZLh5x5Rq/sflVAzDHTKbcPt+LsHb77zi/rZyRn5
wS39OfFFjMtaANz0Nx+Cmdl/njVbz1jUKIOmQc030gPaB6hJO1C1/EFTO7B6XsdlGUGV0tmzMkDS4gIrKS22c6zEbNlKlg8hCy2c
N2gmDLaserPhunLL7l9SuyOryaE3Z9H/2GCJIFUlYWvxIbJr/37GDh9loPC4ckWQrnzYlepDHZOPen0I0nPORXBiGAwZNtRIDUb6
txFHkhlg1WBKw+ZOLjXpPOnwibkfuftdf/P+vp34IsZlKwDmPnId1731T/Ywt/BLuYn18a6n3thAJo6zLZ9/MhiFTJUUVl9m4Ym6
amjqgnsW8kclaQK9pBsflDgxR23bFoJa4tw8sXQ6m2060s1H/nj0gRNHRrM9HMi7bxoK4emUdjtRRJzFENmzdy9Tx49hO11clVtw
0nNX307e1UjpOrt0jaJKJorJNHU87nVGOvPprwpBsVGoRcdw17GpADVaH2mXv7R475Gb9cP3HpYXXNOns1+cuGwFwO3/+2Ouc2z6
dcOGZ7S1lFKFIyEyaj017c8upAo+xqp/5nKpbs2E4GLa/KpqP2d6/EoBSA00hFSuXJU42aa+bTPBOHSGMDG68b/bPVfcfOVfvRGA
m37iD2568PN3vr0e7O8YMS4a2L5rJ2PTJyiKNqKRzFhKXS5a9gj0PO8nvUCS2aOwlFVZpQOq9L71Wy8CGwAAIABJREFUA8tXZCR1
SRr2jkaEUmoystB8hnT4zXv/5lO/AhR9uoiLEpdlGPAb/+GPGP/mgSfWZxZe7MqYlVYImWWhLGjFIj3sZUkeCoyWCCW59zQKT+49
2RkOF33q3GsDwXiCDQTr0zDpZ8q8O8MhfnmY9JpUuQMmBIqxcUyjoXH7xm+6XVvf86R/97qlRn7f86qX+vqm4XeVDXPTlHR181V7
mJ+ew893AIs3lqAskYsedawk3jzKUBFcEHIPWW+okkWqEckC5Gcxlt7vdXkEJQuKC1AvHXVvk7NVDFGhEWwmRxef1/36icc3f/Vv
z9+DeBHgshMAet8h7vjcjXU3P/8bQ532jjwKqhmlKpGSI6HLvLN444g4SiMUxhLFYmOGqiWqO6Oh0WKDw5UO5x02GJy32NIhwWCi
Az3zIZrh1GErk4KYIzHH+oyaz8jLjMXJdmd2Q+23pvLWg/KD1y7dF/lne7GbBsbnXPme3U+5un18/DhxtsVw15EVqbFoJJF47CrD
hZMPG4UosWpVpqkIsVTkKKqoyFkQLSOVoOkdRzSFMUlNUkVhoJsz1M1RFUoTwYCPwlDX7siOL/yniUP3bdCbT5y/B/IC47ITADe8
7a00uws/VsxPP2/AYEyMiCZV3AvM+JIZX+BNepKyKLgIRPCSYu0P4ZyeznjYCw/lvD+0DeYZngAJQtQqi18ixgQyIo5ItKJzQ0Nf
LUz+ue/51Mcfoak//0tvJtux8aNHjxz+jCy0tHTQypUMpe5Tf8GeiXFmV5ewJs/iTE9QnURX3GvpcS6iwUUhCwankkKdmlqNWRVc
FGO74YfH7r7nucffc/loAZeVANDrP83YV27dWI4fed1ILDcYX2BJXmEQvBEWRBkrOixI6vKbhURfRQX/UM7LRYeeWIkCpVWiTSXF
TAwgqh0nzYWRoTcNXnXV3MmOMbx7y5x15i0x+oVgonZdJKBYwEb65iA9N3g4aTrZ+y4asmjIoyUnCXRTRSJUI7m1OBWGCqkPH22/
Zv7o9C79zOVRRPSyygV4ypFjEo8d+clGs/XK4cJnWQyoUdrBU0YlGENpU427hhqGbEYWFKspPh0qcXlOXFUrtAJrHWLN0otnmkMv
gCEx7EqrWI1kQYkqLOQ2ztbMXw888Ylvefxfv/Okjq73H/gcP7XvmceLbndfHuU7JIoprRBjoKErNKCzwEodyBhH5uoYHCzlAZzN
cau0KUnHt1FwGFyw1IJjwDucGiyKEcWYiI9d0BJiKXmQbdOd1uTk1w98+Z33f/aiFnfnApeNBnDgTX9GuxX35YudVw91i1puQa0k
/nqU5DVXxaglmIwJXzBrIr7qO4cqanoknosdWqm2YE1O0zodH2gcZPeuN1/zT//J4lrv/hevennHXbHpT1tSHhSChgy0ZnHx/JZE
O21UDMtlIyOJROsdteCoeYvVFGyUylcQYipnZhCsWmzM8p1T/NvhWf/tk//5hgs3l/OEy0YA3P7BD2d+bOp19Xb4zro46YRIGwiS
mH8mgkOpVc6ueRM5UbRp2sr2JaZ8nH7R1M4hRFPjzDwYKA2t2mBY3Ljpz6c3bbxbXvnyNd9ff9WzcSMDd7eG7J8XToMtS6TwRGf6
F6k7p9ClRCCDxWLIgyFXh9CrQyCk6omkQiqkzsMiddnQMjvDibmfv/t9n8gu8ET6jstCAPzdv/k5OuPHvm1z179oIBqnKpTW4Ws5
oeo2ayVio1IvBYmGrhOmtctU2cabatnHxHJ5tBTdiweJrGMDZN6AOvVZ41syPPq+Z/3Ob50yweEF/9/rYn3f9vc1XfjWSCfosBcW
bCQYuYjnv/JqkkFg1GDVkGFxVW1DNambcrBK1OXIgagg0dJVa+Js6ycbbf/U2d+8tLsKXfICQL9wE5OHDjWGfPmLA/ML2xLfRFJ7
65Ay3aLoUk8+QyQFABxtMUyEgjmrBCeIT47BaJaH9hyDF8GKUCBWqr9TS8TQrdeaRb32n3ds3HpUrn3aKR9Lvv8KGqMjR4a2bPjt
0oRFa6AwMaUtPyS2/7D5X2AYkqkWTRKEeYRGsLjY64OQLjqlJwuIJGJS1XG4Zg0dZxjuuu2bpvU1R2+4q6GfOn6hp9U3XPIC4Mb/
9SFpzc69QFqLL61rYYKJYAQXlFpMCz6uILJ48aAeiVBKxgyGcR/omOUmoFot/B7zrYcL7R5QwLvKBg5KM8/06IB8em7YfuTKD73z
tOmNP/GJ39U50/7biZH4mUnpaC2YpAGtFIIr53/upnLGMJX9HwGrwqAXhkrBRVmq6GS08vsEwaayqZXwF4wPmBJqPpPaPC+cH5t+
wT0f+MTFMLW+4JIWAPqhTzB21zdGw+Tsq2saBn0O8SGrdDlc1NvAglnWCKIIXmCuaNNCKZxJ9rUH5xUbFBOWF/7FYB+HUFLaiHFO
Z+p2fmb70Nt3PfOpC2d6vGu+69p23L357QsjdsGFQBZSONCFZGbYXrlAuTjmH3uFQDWxDk1IMX+jVTOS6rOS3vcVF60oHqWhQkjC
fnBgpvvq5h0HR/Vvj533uZwPXNIC4CvXX2/8Ayeev7Udrs19kJbxqybaqCRNICJLqm0whmaMTPsuLZve3HugbEUkgcRqSxV9zsvU
ToKIsyA+0AmE5lDt3YNX7rp575v/8IyP+Jy/fC31q3Z+sdxY/xDE4EiL3sbe/JcXVeQCWwEiRGMxaqkFQxYFawAEi+JCXFVL6WkO
pnIi1qKRHfPxWplceMndf/6BSzJkfskKgENvfBNH7j3wnEa7/bubumXNaSScghc7VuptgoCkslVTZcEsEY9UffiqGnPVrtKjn15I
PVgVxBgyL9pu1A+bkeE3Pvmf/kBn7Xeujif+k2e0awP132+5+EBJVDEC6FJaLzz8vl0YKIJWpJ96aaj7ZOfHynRz1V+dDAJYIl1J
gmIgCsNktdpM8e9OfO3+Jz/wq//7PMzi/OKSFQBf+t8fzWYOHHjxUNm9wqkXI71ClKtPWU3ax4xWufUK0WYsxsBE0aFtI6UVyoq7
Djwke+9C7oAiEIJS2lpobhz+wPBVVx6zP/uzZ33cp7zmuVz9bVc/6HcM/a9y0IXF2AVrlvsDVH+3aibgeYKJhlrhGCwdDZ/KrgWT
6gyuhSS/I10TMSo4LDE62dzOdm5t2l8/csPtdb37Qs/w3OKSFAAHf+0/EKamv3e0KH/Sadd0XcSLxfl8TUedVKq9VaocgOQ8Kqxj
znvmtKTMDUWvtBecNP/9fEMwIJmObWwcDFdf8Z69r/oZf66O/fRXv8y3N9TfNiv+bjc8qF2JlDE8hHJzoSFV9KMeLIOloR6SBuBJ
vpy4hnhSFC+Kq8yalghNEQZj3YzMhucOxtrzOh+8/mKY6jnDJScA9K47ufcb3xhttLr/bqTT3RJNZKEGpbXkZb5muS8Jya61kSUP
cQSisRRGmPZtFmJBzAxBhHgeF7+u+FpmvFX/RhFFo2ZTnT1bfnfoO67+ljzn2efs3PI927hi596jA8Mj/2XOd5qaOy0ftqDOVxRk
OeK6PPvepWQx2f8NNdRITplgIciyxnYyRIHCKIMxMT6ncoh5DUUZKuxGd2z2tV/74hdH9dZLJ0/gkhMAn3vLn5qxo4dfVGuVz6kV
akQNwaQ0VIxnTSW1p8/3GthXTTUEUGOZCTAVIqVzhMoLJrZ6HKW/wXAlcfwVEpe9evyjpgBXwIYTLn+PFHxo72//bljjcKeNH/rE
G3TPtz3uE+1GeHfLdII2LIWzSBSy2GsF1kcpsOLwUVKsPwpQOWVzbxkoLbXooOJBiBqs9noVri78ezwBUzmBBdDSg1gyzWRoPlzr
7pv+qZn/+tFLZt1cMhMBOPieP2Pi8P37WJh79YBKzUiORIeLgkhJtO01ufyqaVcPaKrgX1WrTf31oOXqTHtoRiUaASKiIQmLPlvA
KlDYJKNSeS4FDVgRim6p7Vp+5PCu7X9xzS/8crdf1/CM1/z44p6n7Xuj3VSbaNpS2xKwxiXm4VJbj37CVA5XxffaiamQhaT6D3dT
hWWPoaxi/nmZQoIJJ78+o0mD6FS+jQ1eyVUpSf0gBoustmUsvPrIwQf36V/d3ed5nh9cUgLgi+//SDb5wLFfHwx8OyFIIQFv07K0
UbGnnMzySHd+8nsrHuhEz2ynQ1fAG4g2JZjY2H81OPkmUtvvYDQ1vvSG7uCgnxrO3rO1xj2Nlz2vb+eX516NHWwc2fWEq/5y8+ZN
vi6GlhaUmUlsijNyiJyO0Fg+fq93QbonlizaROd9SL7hQ79O7XKkKqfGcjf06nC+KL9djk//+tfe8r5LIk/gkhEAd77m3xMenHry
yGLxQjvfciYTCqt4k9RkW9n1Z7s/RYkUoswUXWZDScdaqvYYWNW+CgDRVPLKhURWKgxo8lTrVJZ9o71t43//xz/7onPm+DsZvu9F
P1beP37k3bVGdt+mTcNa1oS2CUjQ85As1Wv9VTlsg+BiUvtzdWfXt3XtUzNg6m50unihOTb7lCPPf1sfT3Z+cEkIAD1+P/feflt9
aKHz+q2duHWDMZS+i7ep1VQvpCfnIlAvEKzQEmW6LGiLoQA0ggn97S1hSLY2onineBFKY1moN8qBffvfsf0J33ZMXvEzfb0GgPxf
XsvI8PB9EwuT7y5r0Q/t2EBpYuppJBBjRcfV2LcW4aKkEmRVlZ8sWvLg+ip+JMVZGaaxdXAxvD6LYUhvbfXxjP3HJSEA/uHP3i3t
2PqJWqv5I7WyNBI9WFCTHGUuVpVyzJk33ehBNC324AxzITIdPF1rq3Jh/XaDJzPGW6GtgWhgITNqn3LNp3Y+/dr/tecXX3neYhLP
+7VfiLWdG/7iwXLmkz5HRzdvRJ3gQ8A4Q9SIrMifONdIkRrB+mQCZaUh8z0h3x+ICDY6yoixXXleZ2zuhbPvfWznCTzmBYB+4S4e
vOn2jXFs6leyWIyKBKKJBBOAmCrFxuQB9mcpAATFJaIwXgxtZ5jsdmiLEN3Z1fM/pfNH0BBZNIFOphgM9cc/bv6Qbb/pgdnJafmO
J/X3AlZey49eTe2KLRPTrvumibmJ+cw5BrZsxGUOHzzGmlSU85xrAFr1FEhanRNLro5cLRmuryaIqmKw4IVQykDzwIlXHb3z3o36
0Qf6ds5+4zEvAG5711+Y8vDUv9zS0X+kUkhhA6WJRBMxqslmjgoC3mpqPXWGECElmEgiB3mxtFSZLdp0q6xCYClcpQ/5OnXoyoOs
GAIYI3TrBp8bRnfs1NnpiU9Lxi1P/B9vPON5nSn+2Qf/IyMbN97iYryudXxMM5uxYeNGrFg0Kup1Kax6bsSALv3sNT5x2DQ05fT1
1QQgaRgGoWFqYrv+H3UPnnj57Ieuf8zmCTymBcCxN7+N+77ypauyudlX5a1mjo3EqoW2qCE10K5Y+7p2HHgtqFKVmU5hqEiKQy8U
XVpBKGxGNLEKCSb+QHCRYKFXpms1HURhqUQ2VGouy5lrXpQyy2iWypatV+v0zOKCbt3410/67meeNd//TPHEJ317pzY68tZF549O
jh/XrFZjaMtmSmcobbpPaOJReCJRlqv1LN0JrZzsKxKLHg0q4E2qyeCCoeEdA8EmDc9EvITTFLWnCVWcekRT+bCBspGPTupvjN19
+Knht67v33n7iMe0ALjlbz+Zheb86wbK1rdZ4yWqomow3mK8RYKpyj4ZVAXjzVl76T2JW66SYv8RpRsNU51IU2oEE0FLTCyBQDCK
T2VoUwXWNZORdImEYlSRmHro+ejxDqZtZMueJ1A8OOcXYvZHO5759OsG3/AbZzeps8Cz/uq12Kt3fHE2j29RwZ8YG4dGjdrmDVC3
FNFjrBCIiLGpDuPDcgZ6n4lZw0eropQSQaEeHEPdjMFu4nkEE+hKuSbd92wgpO7GURQfhUGfy3An2x7H5l9/35dur/XtxH3EY1YA
fPp1r2N8euLJUhYvdD44UXBiHxbz7W96nlYRgdLCbOgwHzyhOqcVlmoNilaMvVOoqW2jYKudUBVCVMrKvPAWBvZto/bgMZ1tuHv9
NXv+YvTxT7xgu38Pz/+Zl4XG1o3vnmrEm6N6XTg+xmBWY3hkAyZzdELAiMEQqpTFRx7jlD4lFZymbD8bDUYNUAn1Hh+4z36Y5FlK
p0qh32DoFj906NgDT7rzle/q78n7gMesABgwbkTmm780VPqtLkasMcnm7LMfXExvx5K0I6F0RFk0yqRvUYghigW1uJji1FI9nNGs
fn29Yp62akQSK5KRZpaYGTbu2oFOHieG7uLMoPmDcvfWY/KSF/V3wqcAecE11K7cPt4clv8WrV+gbLN4YpwBmzO6eUu6fiKyRj7+
WjAq1KIlr0p8GTFVn8FKY+rz06xCJeBBRLFEGuqoLZSbs/nuqyZuu6emd10kmWGniMekAPj4y1/B166/8ftGusWLBoI3SCDEgMWx
ZsbHOUKvrHQUpWuhWxPmtGQ+ekprCWowalMral22edd6PIym9tkY8KRdv6OeDXv2MD8+QTZb6FTOp9zowP952p+/9aJ52l70f3+P
RiO/MTTkU8GpaiiZHZ8iy3JGN21OTU9NcqRplUEVT7MJqwC10pJ7R1ZV++25/eS8lCxPtQWW6E4KViMj3piNi/Li0bb5yTt/842P
qbDgY04A6Mev48Td92yqTc//xkizNWRDQchStp7V5KHv6/l7TW1hmXYqqW1YxypjvsuCEbzL0N4OpRWReC0HRC+ZRiSl2qaIE/X9
+5k9fhxbRCKD84tbNrxj9KmPW7O+//nGU57+tLbfmL1zruHn1QnGR6ZOTCC1nIGNGzDW4n2JsXaZJ3AaOoGJkJeGPKZGH3ali1R7
QqBPk+uhxzNQJRKJQB4NGxYZsWPN13SnF7bre77Z54s4d3jMCYD3vektxi60/tWmVvH04aIQNZ52FigtoP2djiKolSVvlRFhZUkM
L8IUgbGyQ9sZiop3sFQzcK2HU4QyRgpS5MAL5FdcQXnsOFlQiiA6Ozx6nQ5uvuXKt769n1M9I1z77tcwP2puaY666zoS1EXFhMDM
+CS2XqO2cRjrHL70GFPxBE7DZhOgppZasCnBK66k6afQYH/FvyBVHwlI9QPLlCbKqDZkw6L9x7XS/nnbZLv1votGOVsVjykBcN+b
34EW/pqs2f3lDd0ibxDxNtDOlNIkh1C/EauovqhiQvLQ9xJSQGhamAoF82WXKCkM2WOnSS975SRQQFfY/KO7dxFnpjBlSewUSu4O
tbZseuPWZ33PBXf8nQzX/JNndOyGwbdEJ0clojV1hNIzOT2Byx0bN29KJCEl+WweDQ/jUPRsJ9GquWdIST9oStoR6S38/i+6VFw0
pQt7UQqb6kbGGBj21tl7xn9g8iPXf0/xsb/v+7WcCzymBMBtH/5QFh489CsjvnuNoFJiUHXJIaRKamPZZyjJzxBWOJ80hf4lgoqj
LTAe2rSygJiKihwNXVKD0RQNqIQHSaEwJj1UQaBtDCM79zE7MUHRmcWGLmWt4Rc3jLxj88aBW6/4r2/o9yzPGN/3X36Bndt23hKH
a+/0uQSH4oyl7HoWpufIsoyNmzahJmlTiRlRLXKv2ACQkp1Sum9S/euFY7CskUVXFWqp/k6pOB6G89HqspLz1fmFEFLo2UkdGy0j
pctPfOHO5y9ONzfqAxe/FvCYEQDX/errmZiefuqGdvunGmXHFk5oOYeEnEbH4XzK1Os3TEw15aVHLqoGVe55LVhKgUnbZYoukVQ+
nGjxuFScxFZ01qBJcBiD1wjOEJzBXbGbxYlZpN1FQhdEdbYxcGDx6qvfu+utbzxPbs4zx3P/9PfC7uc87YNzA+FAGb2aMlIng7Yy
cWICyXIGN6UQYRE81lliDDixOFLoNErEVzXHs+AYLHI2lA3ckutvWdmvaFOcFwFQaXAiBisGKw6tyseXItDFbJmTHz3+sRt+aOyN
H+r79ZwtHhMCQD/1KSbu/NqgaXV+2apuXv7oTzvT+6ywJrNAFBOT2tqJkcmizZyJqZ9AUBrRpLr6vjqCCEFTbb1oUumq+u4dyMQJ
KFoMeGE0DjGd5c3FrcPvvOLqx43J4644DzM9O8g1wujmzd8qtw29Y7YRm5kGBsuk1kcis5MTZHnO0OgGbO7wPmCMTezK2CNCCS4a
nBqcWpyYVWquCKfw6ZyDiS2PZHrI0qh8weRi2FTSqB2Z+cXFAwc36Wce7N/1nAM8JgTAdX/2F9K6//4Xb2kXL8rChS4+fXIIlSmg
QrCOGQ0cDwVNJ4gR6kUki5DaCwjRpJZjyea3DO/cQTlxHBbnsepxwRA6TovhTZ/QzSPv3vJzL73od/8envTql0Szc8O7p+v+E1bQ
AVVUBCtC8J758SkyY9m0cRNiDFH+X3vnGlvZddXx39p7n3Mf4/d4JvOeSUISoE1DCwokFCgvCdECLY1KadMUCToVBFEhJBQqHkJC
0A8NAkWiTZomBIWgoopCH6kqEkGboBbRRCmKmibpkKlnxmPP2Nce+9r3nnP23osP+zovmjaxZ8Y36PykbfuD5bu37z1rr732Wv+l
BJRgUyq3iZbMO3KftP0yMc+L+Q8nqVYk0ozWTK746+e+9vTbHvmb+4Z5ysNvABY/9nG6C2cPjvb6vzW93mtlwyLB+1JIuiVWa+lZ
w3woWbZKdIINMZ1xlaQrYEg7vxHG9u1lefEsvl/QFCAU4BxFNrIax3fft//aa7ty1WXbvLiXj3yvcPiHr+6ane2PdLNyuaLSaECj
4sTgvafTWUSsYXJ6J2wE1kzyAGwUGpWl6TMawZBHwVxMBdZNYBRaOLpEspjl02vu/avH5qbP3Pbv2z21l2ToDcDDn/68654+c9OI
91fnoRBeYfLIxUQV1GoK6gUh4lgTYaEs6EnqHBRId1deQ2q3nTmy/ftZPXOW2C8RtanjjoFOprEzOfK5PZdf+eD+P7plu5f3irnu
z9/FxO6p/+xNNu5eymNAUis1ExU7aM66uNChMNCamkzpzoPejZlasuBoBkdeGaxPfRyHeTtN1YKRtcxSqJHJNXNNtlJ94H8e/K+h
lQ8bagPw5J/cytqZpWvMav+3cx8yb+NQ9J97KZSUKw5JpspFSzCGji9Y0pJ+ZqgMVBKJTojW0Nq/l7i4gPYLXAATHVEFT9SFMfdM
84eu/PDUj/3Iq1Z25qd/9a1FsWfk1sVx+ySgFnm26k8Ugvd0FzqIc7SmJlEj+KhYLA3NyIMjj4ZML0aIb+uElJFAYR3tYPPdi/Go
P37mdaf/8J+2e2rflqE2AI/+67/l66cWjk6EbFfUKFXTXXDRja0SBrUCuU9BLDD0RVnwPbo2EJ1A5iBzTO3bS//sWcruGiaCDYaM
BiqWIMa39u28R/a1vyZHb9juZW2ayfdfT+t7Ds3F0dadourN849wAsYaQvCsnl0gt4axyQmMTW2HMzXp3l8vXqB3K0SBCthRCTYY
UMclXXY2TywfPf7Fr+b6zHlXat8yQ2sATv/t7VZWZn92V7X+yw2/boxz+OoCR3nPA8kLUMJAItgAEctyiJxFwVg8ytihAyzNzyPd
Pu1gsUEw1uLwRKyutUYfd632nftu+KXh+9S8Qt7xwd+JEwd2fqIzUj0mBPVWKDKDRKHhU4sxjZHVM2dpWsfU+ARGFExAnmvAliqx
hhjVVL8BqXS5FMglMzt68vaip29/+sP/OHQLGLoJAeiJpzlx7NiPmmL1jrHq3M6cYlAK2rygmm9bJ2X9BYFCFE9MIhLOsW4Ms1XJ
OY24IweZnz1JKEsyD1lQHBbVCFLRb+SrvcnpD4WpfXNy3U9u96K2jFzdYmmiOL08FW4JDTm3Fgu8Sdd7uTeYmNKq8wDd+Q6KoTkx
ithIMFXSSEBQNQzzBiCSsgTLQbLXILeJEd+capwpPygnVg/q331zu6f5AobyWPULpbOPffYLN42u99+c+8okZR8zUPTZoq7P82W7
GDTbCJ5Kw7Mlfpt3NlOCj5ENJSxBjCEMrsBMnjF9eB/9hUWc90jlwSnkFrHpbNwzmc638392+/bceuWn7i23stRh4jNPfIV37rn2
dHet/5odeeO17X4U6wV1GTZrJi0HNYiPuJ6ntWOcRt6CtQKNiogFI+e5D2McZPSXiHg2moNvVshUFBqaehChSqbgiDgV6RXlxFqv
O18uLXzlr79x/9BcZwydB1A++hjrpxdft+ucf3e7500w6Vl1qtvefvu7IYA1zxkAHUiGBUAaGdMH9/PU7CyrpUe8pus+PN54kIBo
1NXmyHJv9/RHdnz/FWvbu5rzz+XX/2C/O53ftubXZ0ajqBHoW5JxVIOKoRVz8grkzBJ5dIxMTKLWUEqkMgx1EHhDNNYOWpUpSbg1
V2VvmWXt+bX3dk/NHdLbH93uqT7L0HkAPzA37zqPff3m3Sv9t2SxslWmqcxXn1PdHVYPQASsSZLYiBm0GIuY3HH4skuZmZ1lvVfS
qgKXmAZ5WSXfJs+wJsPbPCxP7vpo+4or7rnszr961Z/9X8xdj9zPzW9822z/1Blp9MNP4TJbOEfLtslDhkTLmM9oBYvzQix6uJFR
bN6gqAq8RNx5bT52fj2AlN8RCaJUJmlFpD1LMDFKJtnkfHGuNzPzrS/ddeJLQ3GfPVQewH/87gdYOD1zjfZWf72FWivJgsZBksiw
oyoETYE+TQdCbOa49MgRjh//Fr4ssdGxXga6vkKMoRkcrhT6kuli5p4au+zwHVe++8b/N67/i/n5m26IY/un/6E77p46p4VKVLJo
cFWqo8gH1X5ODbYy9Bc6lJmFnWOoTbuqmJRZOWzeoKIURCqJqESCgb6BQpNvkFW4sX72vqxvX//Mb9y33dMFhsgA6PF5jj38SLMx
2/nNUSu7Vm0plaTqsDioojN8Z9XY7UaBYA0VaReQzHHkyBFOnjqFeo+UgSxaukRm4jrnDCAWI006ruHDgX0fs1Ptb8pbzl9b72FD
bria0asOzM+NxDtchOlbAAAEAklEQVTLUVflUWlUQh4tbe9w0WHUYILBBIEqwFIHK45sfCIFWWMY6KYMlwXYuAESkhx9FgEVvBiq
VKwk4+v5tMx1/yIsrk7pl7e/qntoDMADt31UVlaLXzlQmnf43prptiE4cANtvHLDAADfTjN/c2ODF1qVzf9FpYyeYATbyDl06CCn
Tp2i7BVoiDSsQyL0cstJUzBLQT8KXhraHxl7vHHZkU/s/bV3DYVreCH5iQ/dEvO9O+8pY/hc7lUzhUwt7ZAe/g1Jd4PBGoeGgC4s
kmFpj48jYl5Q+Tkse4IOvmZRaavSVsgGgasoQkTYETMz1aneuH5s5saz935q25+/bZ8AgH728yw+/NDUeLd3sy17IyNNSwwlUSJR
AhAw4oniUeNRGzY1MAGjMQ0TwaQm4OAxBEQDakJ6jU2NgHGKtXDgwF5OnT5J2V/D4LHRQ6wQeljrUQ2sFD1WnGGp1TgnIyO3jOza
NSc/ft12vx0XHLnccXj/4aXW9PjdIWO16QMTpWUkZjh1iDrAoliMZtiQYytL1VnBN5rYyWlKLF7SUJ4bvOzxPD1BLKoOdBASi3FT
Q1STpiPpYVdN0u5WUwt5o4qNkV2xlevM8vtmvvrEQb3v+MX9578It62vPuDuv79PipXOL+6uyu/rW1tKGbVFTgQKeFZ8ww+KaDZt
8jeUeyS9Z2rAWMEYRUKyhXag9rupPy+CEStHjlxqT8wcj6EM0WqWPhSDG4xeEyoTEWmypMjXHbJz784Hdhzc99Duv/yzYdnMLjg/
88nf5wtv/tMH1nqz/1J09Z2FBOtDCO1AMC9SdnWQiqdC5NzKKRrTu8izMfpLC2SDayITX26ekKSSTQJKhYklqh40DHKNNh973TiQ
bLSFSaRkMAMQIx4w3siIN0fmFpbf+uSnP3MbF03K9v8yFAbgyZkZRjP33812+z1FYQuDXpDDUZLdTj8rSX3Ha2DdGQpSvYZuMeC4
//DhxhMLnUN9aZ0zLp6VmJQKRSCK0M2EwgWUQNubxmh7bLebnvzyVW94Q49P3rXlNb6auPbn3tR7aPn+P37q+OoX9+yePFR0ut+4
pF/Nu5doKBgF1l2g4QtGd02zUq4iIabiqSjPKjV/dza6N1VEKmJI32VDY/wCRRc1eQaCMNpvaXmy6s7Mndxe8cChiKI8dPvHAXit
T/Zo8ub3bud0tsTigw9y8uRJnLG85j03fsffPXP3vSx0OhRlxev/4Pcu0gyHi3Dv40i/mU5hphnN0QPbPaULTrgj6QXao9du80xq
ampqampqampqampqampqampqampqampqampqampqampqampqampqampqampqampqampqampqampqampqampqampqhor/BTeGEXt9
e5sFAAAAAElFTkSuQmCC
'

function install_icon() {
    mkdir -p "$(dirname "$ICON_FILE")"
    base64 -d <<< "$ICON_PNG_B64" > "$ICON_FILE.tmp" 2> /dev/null && mv -f "$ICON_FILE.tmp" "$ICON_FILE"
    rm -f "${OLD_ICON_FILES[@]}"
}

# Lineas Exec/Terminal del acceso del menu: la ventana grafica si hay GTK 3 para Python. Si no, el
# panel en GNOME Terminal a 100x32, donde deja sitio al logo de abajo a la izquierda (a 80x24 la
# ventana lo taparia)
function launcher_exec() {
    # Ruta entre comillas por si lleva espacios (con \, ", ` y $ escapados, como pide el formato .desktop)
    local self=$SELF
    if [[ "$self" =~ [[:space:]\"\`\$\\] ]]; then
        self=$(sed -e 's/[\\"`$]/\\\\&/g' <<< "$self")
        self="\"$self\""
    fi
    if gui_available; then
        printf 'Exec=%s ventana\nTerminal=false\nStartupWMClass=%s\n' "$self" "$GUI_APP_ID"
    elif command -v gnome-terminal > /dev/null; then
        printf 'Exec=gnome-terminal --geometry=100x32 -- %s\nTerminal=false\n' "$self"
    else
        printf 'Exec=%s\nTerminal=true\n' "$self"
    fi
}

# Avisa al menu de aplicaciones de que han cambiado los accesos
function refresh_launchers() {
    command -v update-desktop-database > /dev/null && update-desktop-database -q "$1" 2> /dev/null
    touch "$1"
}

# Si el acceso antiguo esta anclado en el dock de GNOME, el dock lo sigue buscando por su nombre de
# archivo y lanza la version que tiene en cache (con la ruta vieja): se cambia por el nuevo, en su sitio
function replace_favorite() {
    command -v gsettings > /dev/null || return 0
    local favorites=$(gsettings get org.gnome.shell favorite-apps 2> /dev/null)
    [[ "$favorites" == *"'$1'"* ]] || return 0
    if [[ "$favorites" == *"'$2'"* ]]; then
        favorites=${favorites//"'$1', "/}
        favorites=${favorites//", '$1'"/}
        favorites=${favorites//"'$1'"/}
    else
        favorites=${favorites//"'$1'"/"'$2'"}
    fi
    gsettings set org.gnome.shell favorite-apps "$favorites" 2> /dev/null
}

LAUNCHER_DIR="$HOME/.local/share/applications"
LAUNCHER="$LAUNCHER_DIR/lampp-version-manager.desktop"

# Pone al dia los accesos creados por versiones anteriores (nombre, icono y lo que abren)
function update_launchers() {
    local apps=$LAUNCHER_DIR launcher=$LAUNCHER

    # El acceso antiguo se renombra: GNOME no siempre relee un .desktop que cambia de contenido,
    # pero con otro nombre de archivo lo trata como una aplicacion nueva (nombre e icono incluidos)
    local old changed=0
    for old in "$apps/lvm-instalador.desktop" "$apps/php-version-loader.desktop" "$apps/php-version-manager.desktop"; do
        [ -f "$old" ] || continue
        replace_favorite "$(basename "$old")" "$(basename "$launcher")"
        if [ -f "$launcher" ]; then
            rm -f "$old"
        else
            mv -f "$old" "$launcher"
        fi
        changed=1
    done

    # Un acceso creado por una version anterior se actualiza al nombre y al icono actuales
    if [ -f "$launcher" ]; then
        cmp -s "$ICON_FILE" <(base64 -d <<< "$ICON_PNG_B64" 2> /dev/null) || install_icon
        if ! grep -qxF "Name=$APP_NAME" "$launcher" || ! grep -qxF "Icon=$ICON_FILE" "$launcher"; then
            sed -i -e "s|^Name=.*|Name=$APP_NAME|" -e "s|^Icon=.*|Icon=$ICON_FILE|" \
                -e "s|^Comment=.*|Comment=Instalar, cambiar y desinstalar versiones de XAMPP y PHP|" "$launcher"
            changed=1
        fi
        local exec_lines=$(launcher_exec)
        # El acceso del paquete (.deb) abre el script de /opt/lvm-instalador, que es de root: una copia
        # que se ejecute desde otra carpeta (Descargas, que es tuya y la puede cambiar otro programa)
        # no se lo lleva a ella, porque en esa ventana se escribe la contraseña
        if grep -q '^Exec=.*/opt/lvm-instalador/' "$launcher" && [[ "$SELF" != /opt/lvm-instalador/* ]]; then
            exec_lines=$(grep -E '^(Exec|Terminal|StartupWMClass)=' "$launcher")
        fi
        if [ "$(grep -E '^(Exec|Terminal|StartupWMClass)=' "$launcher")" != "$exec_lines" ]; then
            # Se quitan las lineas viejas y se ponen las nuevas detras de Comment=
            awk -v lines="$exec_lines" '/^(Exec|Terminal|StartupWMClass)=/ { next } { print } /^Comment=/ { print lines }' \
                "$launcher" > "$launcher.tmp" && mv -f "$launcher.tmp" "$launcher"
            changed=1
        fi
    fi
    [ $changed -eq 1 ] && refresh_launchers "$apps"
    if [ -f "$launcher" ]; then
        for old in lvm-instalador.desktop php-version-loader.desktop php-version-manager.desktop; do
            replace_favorite "$old" "$(basename "$launcher")"
        done
    fi
}

# Crea el acceso del menu de aplicaciones
function write_launcher() {
    mkdir -p "$LAUNCHER_DIR"
    install_icon
    cat > "$LAUNCHER" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Instalar, cambiar y desinstalar versiones de XAMPP y PHP
$(launcher_exec)
Icon=$ICON_FILE
Categories=Development;
EOF
    chmod +x "$LAUNCHER"
    refresh_launchers "$LAUNCHER_DIR"
}

function offer_command_install() {
    [ "$DRY" -eq 1 ] && return 0

    local marker="$LOG_DIR/.accesos-ofrecidos-pvm"
    local launcher=$LAUNCHER
    local need_cmd=0 need_lvm=0 need_launcher=0

    update_launchers

    # Comandos creados por versiones anteriores que apuntan a otro archivo del instalador (por
    # ejemplo al pvm-instalador.sh de las versiones 1.5 a 1.7): lvm-instalador y lvm se reapuntan
    # y pvm-instalador, el nombre de esas versiones, se quita. Se ofrece aunque ya se ofreciera antes
    local link old_links=() drop_links=()
    # (los que llevan al de /opt/lvm-instalador, el del paquete, no se tocan: es de root)
    for link in /usr/local/bin/lvm-instalador /usr/local/bin/lvm; do
        [ -L "$link" ] && [ "$(readlink "$link")" != "$SELF" ] \
            && [[ "$(readlink "$link")" == */[lp]vm-instalador.sh ]] \
            && [[ "$(readlink "$link")" != /opt/lvm-instalador/* ]] && old_links+=("$link")
    done
    link=/usr/local/bin/pvm-instalador
    [ -L "$link" ] && [[ "$(readlink "$link")" == */[lp]vm-instalador.sh ]] && drop_links+=("$link")

    [ -f "$marker" ] && [ ${#old_links[@]} -eq 0 ] && [ ${#drop_links[@]} -eq 0 ] && return 0
    command -v lvm-instalador > /dev/null || need_cmd=1
    command -v lvm > /dev/null || need_lvm=1
    [ ${#old_links[@]} -gt 0 ] || [ ${#drop_links[@]} -gt 0 ] && need_cmd=1
    [ -f "$launcher" ] || need_launcher=1
    [ $need_cmd -eq 0 ] && [ $need_launcher -eq 0 ] && return 0

    mkdir -p -m 700 "$LOG_DIR"
    touch "$marker"

    local text="¿Quieres crear accesos directos para abrir este instalador facilmente?\n\n"
    [ $need_launcher -eq 1 ] && text+="  - Icono '$APP_NAME' en el menu de aplicaciones\n"
    command -v lvm-instalador > /dev/null || text+="  - Comando 'lvm-instalador' en la terminal\n"
    for link in "${old_links[@]}"; do
        text+="  - Comando '$(basename "$link")' (ya existe): que abra este archivo\n"
    done
    for link in "${drop_links[@]}"; do
        text+="  - Quitar el comando antiguo '$(basename "$link")' (ahora es 'lvm-instalador')\n"
    done
    [ $need_cmd -eq 1 ] && [ $need_lvm -eq 1 ] && text+="  - Comando 'lvm' en la terminal ('lvm use 8.4', 'lvm instalador'...)\n"
    text+="\nApuntaran a: $SELF\n(no muevas ni borres este archivo despues)"

    ui_yesno "$text" || return 0

    [ $need_launcher -eq 1 ] && write_launcher

    if [ $need_cmd -eq 1 ]; then
        [ "$UI" == "whiptail" ] && clear
        echo "Para crear el comando se necesita la contraseña de administrador (sudo):"
        command -v lvm-instalador > /dev/null || sudo ln -sf "$SELF" /usr/local/bin/lvm-instalador
        [ $need_lvm -eq 1 ] && sudo ln -s "$SELF" /usr/local/bin/lvm
        for link in "${old_links[@]}"; do sudo ln -sfn "$SELF" "$link"; done
        for link in "${drop_links[@]}"; do sudo rm -f "$link"; done
    fi

    ui_msg "Accesos creados. A partir de ahora puedes abrir el instalador desde el menu de aplicaciones o escribiendo 'lvm-instalador' en la terminal."
}

# Acerca de: que hace el instalador y la lista de versiones con sus cambios (la ultima, arriba)
ABOUT_TEXT="Herramientas de desarrollo web en local. Para Linux.

QUE HACE
- Instala varias versiones de PHP, de la 7.4 a la 8.5 y cualquier parche
  (8.3.10...), cada una con su propia pila: Apache, PHP-FPM, MariaDB,
  ProFTPD, Perl y phpMyAdmin, en /opt/lampp-X.Y.Z y con sus propias bases
  de datos. Cada rama de PHP lleva componentes compatibles entre si.
- Instala XAMPP completos para proyectos antiguos (equipos x86_64).
- Solo hay una versión activa (/opt/lampp). Se cambia sin tocar los
  proyectos de /opt/htdocs ni los virtual hosts.
- Actualiza cada versión a los últimos parches de su rama, muestra sus
  bases de datos y desinstala versiones (con copia en ~/nexum-backups,
  si se pide).
- No instala PHP ni MariaDB en el sistema.
- Correo de pruebas: lo que mandan las webs locales va a Mailpit y no
  llega a nadie.

VERSIONES

1.57.10 (10 nov 2026)
- El manual, dentro del programa: «Ayuda», en el menú ☰, lo abre en el
  navegador en el capítulo de la página en la que estás (en la terminal:
  lvm-instalador manual). No necesita conexión y se actualiza con el
  programa.
- El manual enseña un capítulo cada vez, con «← Anterior» y
  «Siguiente →» al final; el buscador sigue buscando en todo.

1.57.9 (10 nov 2026)
- Desplegables con buscador: los de 8 opciones o más (proyectos, BBDD,
  carpetas, versiones...) se abren con «Buscar…». Se escribe y la lista
  se queda con lo que lleva ese texto; las flechas eligen, Intro la
  escoge y Esc cierra.
- ▶ / ■ en el visor de arriba, a la derecha de Apache y MariaDB: ■ para
  y desactiva la versión, ▶ la arranca. Sin ninguna activa, ▶ despliega
  las versiones instaladas (la última que se usó, la primera) para
  arrancar una.
- Limpieza, en Configuración: la caché de descargas, las copias de
  seguridad, el correo de Mailpit, los registros del programa y de cada
  versión (se vacían), la caché de todos los proyectos, los temporales
  que deja el programa y las sesiones de PHP, cada cosa con lo que ocupa.
  Se marca lo que se quiere limpiar (en la terminal: limpieza y limpiar).
- Limpiar proyecto, en el ⋮ de cada proyecto: su caché, sus registros y,
  en WordPress, los restos de las actualizaciones. Nunca las imágenes
  (uploads ni img). En la terminal: limpiar-proyecto.

1.57.8 (10 nov 2026)
- Copiar una BBDD a una versión parada (recrear un proyecto en otra
  versión de PHP, copiar o descargar una BBDD): su MariaDB temporal se
  daba por caído nada más arrancarlo y la copia fallaba con «No ha
  arrancado», aunque estuviera arrancando bien. Ahora se espera a que
  esté listo.

1.57.7 (10 nov 2026)
- Copias de seguridad, solo si se piden: al cargar un .sql sobre una
  BBDD con tablas, sustituir una BBDD al copiarla o replicarla, reparar
  las tablas del sistema, pasar un proyecto al Apache de Docker,
  actualizar un proyecto o actualizar una versión que empieza con BBDD
  vacías, la copia de lo de antes se guarda solo si se marca «Guardar
  antes una copia» (en la terminal, --copia). Sin ella, se avisa de que
  no se podrá recuperar. Borrar una BBDD, una versión o un proyecto,
  igual que antes, pero con la casilla desmarcada de partida.
- La carpeta de las copias se llama ahora ~/nexum-backups: la de antes
  (~/lvm-copias) se renombra sola la primera vez, si no hay ya otra.
- Las copias de los ficheros que el programa cambia por su cuenta (el
  de hosts, los vhosts, la configuración de los proyectos al cargarlos,
  lo que cambia asegurar) ya no se guardan siempre: se encienden en
  Configuración, Carpetas (o lvm-instalador copias-ficheros si). La
  caché vieja de una tienda, sin ellas, se borra (se rehace sola).
- Configuración, Carpetas: «Borrar…» las copias de seguridad, con
  cuántos ficheros hay y cuánto ocupan (o lvm-instalador copias vaciar).

1.57.6 (10 nov 2026)
- Caché de descargas: el código de cada componente que se instala
  (PHP, Apache, MariaDB, phpMyAdmin...) se guarda ya comprobado en
  /var/cache/nexum-stack. Al reintentar una instalación que falló no se
  descarga otra vez, y si la web de un componente no responde se usa
  el de la caché en vez de cancelar. Se ve y se vacía en
  Configuración, Carpetas (o lvm-instalador descargas).
- Mantenimiento: el código va ahora en ficheros por partes, también
  las dos ventanas (un fichero por apartado), y se revisa solo
  (ShellCheck, ruff y la compilación de la ventana del Mac) en cada
  cambio. Se quita lo que no se usaba; nada cambia por fuera.
- Arreglar los certificados: usado dos veces seguidas, ya no vuelve a
  rehacer la lista de certificados del sistema sin hacer falta.

1.57.5 (9 nov 2026)
- Configuración: arriba, en grande, el nombre del apartado abierto
  (con su icono y lo que hace), no «Configuración»; el correo de
  pruebas se enciende con el interruptor de al lado.
- Apariencia: en tres bloques, cada uno con su título (iconos del
  menú lateral, apartados del menú lateral y visor de los proyectos).
  Los botones del visor están aquí: ya no hay un apartado aparte (salían
  dos veces).
- Seguridad entre webs: explicada en cuatro puntos (el problema, lo
  que hace la barrera, cuándo apagarla y dónde se aplica).

1.57.4 (9 nov 2026)
- Diálogos que piden confirmar varios cambios (crear un dominio,
  copiar o replicar una BBDD, cargar o actualizar un proyecto, instalar
  versiones, Actualizar todo): empiezan por «Qué se va a realizar» y
  los cambios van numerados, a la izquierda y separados entre sí.

1.57.3 (8 nov 2026)
- Actualizar versiones de PHP: si GitHub no da la suma sha256 de
  ProFTPD (su descarga respondía 504 y la actualización fallaba al
  momento), se pide por la API de GitHub, del mismo repositorio. Si
  una descarga falla, el informe del error dice por qué.

1.57.2 (7 nov 2026)
- Configuración: sus apartados, en una columna pegada al menú
  lateral, y en filas (Docker y el correo de pruebas siguen en
  tarjetas). El correo de pruebas se enciende con el interruptor de su
  título; en la dirección del Apache de Docker, Guardar va debajo de
  sus campos.
- Parches nuevos: en lugar de preguntar al abrir, sale un aviso arriba
  (al lado del visor) con lo que tiene un parche y si conviene ponerlo.
  «Ahora no» lo deja hasta que salga otro.

1.57.1 (7 nov 2026)
- Instalaciones en segundo plano: la ventana de una instalación o
  actualización tiene «Seguir en segundo plano» (también con Esc) y
  el programa se puede usar mientras tanto. Al lado del visor sale una
  flecha verde que late, con lo que hace
  («Actualizando…», «Instalando…») y el porcentaje; al pulsarla vuelve la
  ventana. Si acaba bien, avisa; si falla, la ventana vuelve sola. No
  se puede lanzar otra tarea hasta que acabe.
- Apariencia, en Configuración: los iconos del menú lateral en color
  o de un color, como el texto; Docker, Node y PHP con su logotipo y su
  tipografía; qué apartados salen en el menú (Proyectos y Configuración,
  siempre), y los botones del proyecto. Bases de datos, con su icono de
  discos apilados.

1.57.0 (6 nov 2026)
- Proyectos de Node: nueva pestaña Node para los proyectos de htdocs
  hechos con Astro, Next, Nuxt, SvelteKit o Vite. Cada uno se arranca en
  desarrollo o compilado, con la versión de Node que pide y sus
  dependencias, y el compilado se puede compartir con un túnel de
  Cloudflare. En la terminal: node-arrancar, node-parar y node-registro.

1.56.33 (6 nov 2026)
- Correo de pruebas: la bandeja de Mailpit se ve dentro de la ventana,
  debajo de sus tarjetas, y el botón Correo lleva a ella en lugar de
  abrir el navegador. Los enlaces de los correos sí se abren en el
  navegador al pulsarlos.

1.56.32 (6 nov 2026)
- Instalaciones y actualizaciones: encima de «Ver registro» sale la
  lista de lo que se está haciendo y cada paso se marca con un check al
  acabar. También al actualizar un proyecto o los componentes, al montar
  un proyecto nuevo, en Docker, Mailpit, cloudflared y phpMyAdmin.

1.56.31 (6 nov 2026)
- Proyecto cargado: los botones se llaman «Actualizar» e «Importar». Al
  pasar por encima dicen «Actualizar proyecto» e «Importar imágenes de
  producción».

1.56.30 (5 nov 2026)
- Proyecto cargado y Docker: botón «Importar imágenes» en WordPress y
  PrestaShop. Se muestra u oculta en Personalizar los botones.
- Iconos nuevos en «Actualizar proyecto» e «Importar imágenes».

1.56.29 (5 nov 2026)
- Proyecto cargado: el botón Log abre el error_log de Apache. El de
  web.local sigue en Herramientas, Registro de errores.

1.56.28 (5 nov 2026)
- Actualizar proyecto: se puede actualizar la BBDD, el código o los
  dos. Sin fichero de BBDD, dice que se sigue usando la misma y no la
  toca.
- Actualizar proyecto: al acabar se comprueba que wp-config.php o
  parameters.php han quedado con la BBDD y la dirección locales, sin
  desmontar ni volver a cargar a mano. Si no, lo dice.
- Actualizar proyecto: el recuadro azul sale solo con el fichero
  incorporado o al arrastrarlo encima, y el nombre de la BBDD se ve en
  azul, como texto.

1.56.27 (5 nov 2026)
- Proyecto cargado: botón «Actualizar proyecto». En su ventana se
  arrastra o se elige la BBDD descargada de producción y su código (un
  .zip, un .tar.gz o una carpeta), y se elige entre fusionar o
  sobrescribir la carpeta. Si es un repositorio, antes de copiar
  pregunta si hacer git pull y avisa de lo que no tiene commit o no se
  ha subido.
- Lo sustituido o quitado del proyecto queda en ~/lvm-copias, su .git
  no se toca y, al acabar, el proyecto se vuelve a cargar para que su
  configuración apunte a la base y al dominio locales.
- En la terminal: lvm-instalador actualizar-proyecto.

1.56.26 (5 nov 2026)
- Nuevo proyecto, buscador de repositorios: los resultados salen en la
  propia ventana, debajo del buscador, en vez de en un desplegable que
  podía no verse. Se eligen con el ratón, con las flechas o con Intro.
- Repositorios: botón para copiar el repositorio. Al pegarlo en el
  buscador de Nuevo proyecto, queda elegido.

1.56.25 (5 nov 2026)
- Nuevo proyecto, buscador de repositorios: encuentra el repositorio al
  momento. La lista se carga en segundo plano al abrir el programa y
  se pone al día con GitHub. También salen los que no llevan uno de
  los prefijos de Configuración.
- Repositorios: la lista tardaba unos minutos y a veces no llegaba a
  cargar. Cada lectura del token de gh esperaba 15 segundos sin motivo.

1.56.24 (5 nov 2026)
- Los mensajes al dejar el ratón encima de botones, interruptores e
  indicadores son ahora cortos y dicen solo lo que hacen. Las
  explicaciones largas siguen en los símbolos ⓘ.
- Proyecto cargado: el interruptor del dominio lleva el título «Falsear
  Host» y, cuando está falseado, «Host falseado».
- Botón Log: icono nuevo, un folio verde con «LOG» escrito.

1.56.23 (5 nov 2026)
- Proyecto cargado: si su carpeta tiene un dominio en los vhosts, junto
  a sus botones sale ese dominio con un interruptor para falsearlo o
  dejar de falsearlo sin ir a Dominios y hosts.
- Dominios y hosts: «Host falseado» ocupa 1/3 de la pestaña y, a su
  lado, «Nuevo proyecto con dominio falseado» ocupa los otros 2/3.
- Dominios y hosts, botón «Ver fichero de hosts»: enseña /etc/hosts,
  solo para leerlo, con los dominios que se pueden falsear delante (los
  que tienen vhost, estén o no en el fichero).

1.56.22 (3 nov 2026)
- Dominios y hosts, «Crear y falsear»: el botón se veía azul aunque no
  se pudiera pulsar (le faltaba un dominio válido o la carpeta) y no
  hacía nada. Ahora se ve apagado y debajo dice lo que falta; con todo
  puesto, lo que va a crear (https://dominio → carpeta).
- El dominio se puede pegar como dirección (https://www.mitienda.com/):
  se queda solo con el nombre.

1.56.21 (3 nov 2026)
- WordPress: el wp-config.php lleva siempre WP_SITEURL y WP_HOME con
  la dirección local (https://web.local o su dominio propio). Si
  entraba en la base pero le faltaban, se daba por bueno y la web
  redirigía a producción: ahora, al cargar el proyecto (o en Nuevo
  proyecto), se le añaden sin tocar el resto del fichero.

1.56.20 (3 nov 2026)
- Nuevo proyecto con un WordPress: al acabar de importar su BBDD se
  prepara su wp-config.php para local (la base, root y localhost, y
  WP_HOME). Se hacía al cargarlo, antes de importarla, y como la base
  aún no existía se quedaba sin hacer (solo se repetía con PrestaShop).
  Si después pegas encima el código de producción, vuelve a cargar el
  proyecto: su wp-config.php vuelve a la base local.

1.56.19 (3 nov 2026)
- Nuevo proyecto: al escribir en el buscador de repositorios, la lista
  sale con sus nombres (salían las filas vacías: había que adivinar
  cuál era cada una).

1.56.18 (3 nov 2026)
- Icono junto al reloj: al cerrar la ventana, Nexum sigue en él. Su
  menú abre la ventana, arranca o para la versión activa (con su
  estado), abre web.local y sale. Se quita en Configuración → Programa
  («Dejar en la bandeja al cerrar»); sin él, cerrar la ventana cierra
  el programa como antes. Hace falta gir1.2-ayatanaappindicator3-0.1
  (el paquete .deb lo instala).

1.56.17 (3 nov 2026)
- Terminal: copia y pega con Ctrl+Mayús+C y Ctrl+Mayús+V (también
  Ctrl+Insert y Mayús+Insert), como en la Terminal de GNOME, y con el
  botón derecho (Copiar, Pegar y Seleccionar todo).
- Terminal: «Proyecto cargado» ya lleva a su carpeta (se quedaba en la
  de los proyectos), y lo mismo al abrirla. Nuevo botón «Vaciar DNS»:
  escribe sudo resolvectl flush-caches (la contraseña, en la terminal).

1.56.16 (30 oct 2026)
- Ventana: al cerrarla, el programa se cierra del todo (si algo lo
  retuviera, a los 5 s se corta). Al abrirla se cierran las ventanas de
  versiones anteriores que se hubieran quedado en marcha sin ventana.
- Ventana más ligera: lo que pregunta cada 20 s va en una sola orden y
  gasta casi la mitad de CPU (la revisión de seguridad de las versiones
  solo se repite si cambian sus ficheros y las fechas de las BBDD de
  todas las versiones se leen de una vez); la pestaña Proyectos ya no
  se rehace si no ha cambiado nada.

1.56.15 (30 oct 2026)
- Instalar una versión de PHP: un repositorio roto de otro programa
  (un PPA sin versión para tu Ubuntu, una clave caducada como la de
  Warp) ya no impide instalarla. Solo se instalan las librerías que
  faltan (si están todas, ni se llama a apt); si apt-get update no
  puede leer algún repositorio, se dice cuál y se sigue con las listas
  que ya había. Solo se para si de verdad falta un paquete, y entonces
  dice qué repositorio arreglar.
- Ventana: al buscar los parches nuevos se quedaba dando vueltas a toda
  CPU (un núcleo entero) y, al cerrarla, su proceso seguía en marcha;
  con cada vez que se abría se sumaba otro. Ya no: al actualizar,
  cierra las que tengas abiertas y vuelve a abrirla.

1.56.14 (30 oct 2026)
- Descargar una BBDD: ya no falla («Unable to lock ibdata1») si la
  MariaDB de esa versión la tiene en marcha Docker (sin red). Se usa
  esa MariaDB en lugar de arrancar otra sobre los mismos datos, y al
  terminar sigue en marcha para Docker. Lo mismo al copiar una BBDD a
  otra versión.
- Visor de arriba: sin el botón Encendidos. Al pulsar Apache o MariaDB
  se abren sus servicios (lo que antes salía en la flecha), con
  «Parar y desactivar» o «Arrancar» la versión entera arriba.
- Bases de datos: «Subir o actualizar una BBDD» va antes de la tabla,
  más compacto (el fichero, la BBDD de destino, el proyecto y Cargar
  en columnas) y en un visor un poco hundido.
- Configuración: a la izquierda, una columna con sus apartados (Parches
  nuevos, Vhosts y hosts, Correo de pruebas, Docker, GitHub, Carpetas…);
  a la derecha, solo lo que se puede cambiar del elegido.

1.56.13 (30 oct 2026)
- Nuevo proyecto: en el paso 1, el repositorio se elige de los de
  GitHub (los de la pestaña Repositorios, escribiendo parte de su
  nombre): se rellenan solos su dirección SSH y su carpeta. Se puede
  seguir escribiendo la dirección de otro. Un paso 4 pregunta si falsear
  su dominio de producción (ya puesto si el repositorio tiene su web en
  GitHub): al terminar de montarlo, se falsea como en Dominios y hosts.
- Terminal: el mismo hueco arriba que abajo de su caja.

1.56.12 (30 oct 2026)
- Terminal abajo de la ventana: el botón Terminal de arriba (en lugar
  de Localhost) la enseña y la esconde. Con el aspecto del visor, un
  poco hundida; es la de la Terminal de GNOME (VTE), con tu shell, en la
  carpeta del proyecto cargado («Proyecto cargado» vuelve a ella; el
  borde se arrastra para cambiar su alto). Al esconderla sigue abierta.
  Si falta VTE, dice cómo ponerla: sudo apt install gir1.2-vte-2.91.

1.56.11 (30 oct 2026)
- Pestaña Docker: el puente hasta la BBDD de LAMPP en vivo sale con su
  nombre («Puente a la BBDD de lampp-8.4 (en vivo)»), dice qué
  proyectos lo usan y se puede parar o arrancar (antes salía como «(sin
  proyecto)» y sin botones). La MariaDB común de Docker ya no cuenta
  como usada por los proyectos que van en vivo con LAMPP.
- Repositorios: detrás de «Clonar» o «Traer cambios», el logotipo de
  GitHub abre el repositorio en GitHub (sus cambios, ramas y pull
  requests). La carpeta de los ya clonados va debajo del nombre, y así
  todos los botones quedan a la misma altura.

1.56.10 (30 oct 2026)
- Docker con la BBDD de LAMPP en vivo (WordPress): un proyecto de
  Docker puede usar la BBDD de cualquier versión de PHP de LAMPP, la
  misma que web.local, sin copias: lo que cambias en un lado se ve en el
  otro. Si la MariaDB de esa versión no está en marcha, se arranca solo
  ella, sin red (no choca con la de la versión activa); se para sola
  cuando ningún proyecto de Docker la usa, y al activar esa versión en
  LAMPP pasa a la de siempre. Se elige al montar el proyecto en Docker
  («Cómo: en vivo») o después, en su fila de la pestaña Docker. Las
  tiendas PrestaShop siguen con su copia: guardan su dominio en la BBDD
  y una misma BBDD no puede servir a web.local y a Docker a la vez. En
  la terminal: docker-bd <proyecto> lampp <versión> | docker.

1.56.9 (30 oct 2026)
- Docker: las imágenes y enlaces que un WordPress guardó trabajando con
  LAMPP (https://web.local/wp-content/…, o su dominio propio) salen del
  contenedor: antes se pedían a LAMPP y, sin él en marcha o con otro
  proyecto en web.local, no se veían. La BBDD no se toca: se cambian en
  lo que devuelve la web (también escapadas, como las de Elementor). Los
  proyectos de antes se arreglan al arrancarlos.
- Configuración, GitHub: la organización o cuenta se puede escribir
  también como su dirección (https://github.com/mi-empresa) o con @, se
  comprueba que existe, y si no vale se dice en una ventana y lo escrito
  se queda (antes volvía la de antes sin decir nada).

1.56.8 (29 oct 2026)
- Los proyectos de Docker sin visitas se paran solos (Configuración,
  Docker): uno que lleva las horas elegidas (3 de partida; de 1 a 24, o
  nunca) sin ninguna visita, tampoco por el túnel, se para, y con él lo
  común que ya no use nadie (su MariaDB, el Apache de Docker). Se mira
  cada 15 minutos, también con la ventana cerrada (un temporizador de systemctl --user). Al entrar
  en un proyecto parado, su web lo dice en vez de dar un error. En la
  terminal: docker-reposo.
- Pestaña Repositorios (como DevHub): los repositorios de la
  organización o cuenta de GitHub que se elija en Configuración, solo
  los de sus prefijos (de partida dob-wordpress- y dob-prestashop-; se
  pueden añadir otros, como los de Shopify) o todos, con un buscador.
  «Clonar» lo clona por SSH, con tu clave, en la carpeta de proyectos.
  Si ya está clonado en un proyecto, se pregunta si aplastarlo: se
  traen sus cambios con git pull y, si chocan con los tuyos, no se toca
  nada y se dice. La lista se lee con un token de GitHub (se guarda en
  el llavero de la sesión, no en un fichero) o con la sesión de gh, y la de la
  última vez sale al momento. En la terminal: github, github-conectar,
  repos y repo-traer.
- Parches nuevos (Configuración): lo que tiene un parche publicado en
  cada versión de PHP (PHP, Apache, MariaDB, ProFTPD, Perl y
  phpMyAdmin), en las imágenes de Docker (las MariaDB comunes,
  phpMyAdmin y PHP, frente a Docker Hub, sin descargar nada), Mailpit y
  cloudflared, con «Actualizar todo». Se busca al abrir la ventana
  cuando toca buscar una versión nueva del programa y, si hay algo, se
  ofrece actualizarlo. Las MariaDB comunes de Docker se ponen al día
  solas al cambiar de parche. En la terminal: componentes y
  componentes-actualizar.
- Correo de pruebas (Configuración): sus tres tarjetas en una fila.
- Configuración, Túnel de Cloudflare: cloudflared y el registro, juntos
  en una fila, y el túnel abierto debajo, a lo ancho (antes cada uno
  quedaba suelto).

1.56.7 (29 oct 2026)
- Túnel de Cloudflare: cuánto dura y si se bloquea el admin se eligen
  al pulsar «Compartir», para ese proyecto y ese túnel. Cada túnel
  lleva una contraseña nueva al azar (se ve al abrirlo, para copiarla);
  la de un túnel no vale para el siguiente. Configuración, Túnel de
  Cloudflare deja solo cloudflared, el túnel abierto y su registro. En
  la terminal: tunel-abrir <dirección> [carpeta] [--horas 1-12]
  [--admin bloquear|permitir]; ya no hay tunel-config.
- Menos memoria con varios proyectos de Docker a la vez: el PHP de cada
  contenedor abre sus procesos al llegar peticiones y los cierra a los
  20 s sin trabajo (un proyecto en marcha sin usar pasa de unos 190 MB
  a unos 11 MB). Los de antes se ponen al día solos al arrancarlos. El
  Apache de Docker espera con un proceso, no con tres.
- El consumo de arriba no lee nada con la ventana minimizada, y lee
  menos cada vez (lo que no cambia de cada proceso, una sola vez).

1.56.6 (28 oct 2026)
- Imágenes de producción: «Guardar» funciona también con el dominio que
  ya estaba guardado (antes solo se podía quitar o cancelar). Así se
  vuelve a aplicar, también en el Apache de Docker.

1.56.5 (28 oct 2026)
- Imágenes de producción también en Docker: en un WordPress del Apache
  de Docker, lo que falte de wp-content/uploads se pide a su web real
  (con el mismo dominio que con LAMPP: «Imágenes de producción…» vale
  para los dos). En una tienda, «Descargar las imágenes que faltan»
  usa la BBDD de Docker si no está en la versión activa (su dominio de
  producción se guarda al pasarla a Docker; si no se sabe, se pide).
  Botón «Imágenes de producción…» en el visor de Docker.

1.56.4 (28 oct 2026)
- Configuración más clara: cada ajuste en su tarjeta, de dos en dos
  (como los visores de las otras pestañas), con su explicación entera
  y sus botones en la tarjeta. Docker junta la dirección y los dos
  puertos en una sola; lo que va solo (la barrera entre webs, los
  botones del visor, el túnel abierto) va a lo ancho.
- Botones del proyecto: el configurador va en horizontal (la lista a la
  izquierda; el estilo, el tamaño y la vista previa a la derecha), y
  cabe en la pantalla de un portátil: el botón Guardar ya no se queda
  fuera.

1.56.3 (28 oct 2026)
- Proyecto nuevo desde un repositorio privado: si su dirección https
  de GitHub, GitLab o Bitbucket no se puede clonar (pide usuario y
  contraseña), se prueba sola la misma por SSH
  (git@github.com:usuario/repositorio.git), con tu clave. Con otros
  servidores, como siempre: su dirección SSH a mano.
- DNS de *.docker.test (Configuración, Docker, «Activar»): un DNS
  mínimo, solo en este equipo, que contesta a cualquier
  <algo>.docker.test. Los proyectos del Apache de Docker pasan a
  .docker.test (su configuración, el dominio de las tiendas en su BBDD
  y el certificado) y dejan de ir en /etc/hosts: añadir proyectos o
  versiones de Docker ya no pide la contraseña por los dominios.
  web.local, los proyectos de siempre y los dominios falseados de las
  tiendas no cambian (siguen en /etc/hosts, que se mira antes). Si el
  DNS no contesta al activarlo, se quita y todo sigue como estaba.
  .local es de mDNS (Bonjour, Avahi): un DNS para *.docker.local no se
  consultaría nunca. En la terminal: docker-web dns activar|quitar.
- El certificado del Apache de Docker vale para *.docker.local y
  *.docker.test.

1.56.2 (27 oct 2026)
- Botones del proyecto: «Solo el icono» y «Icono y nombre» son
  cuadrados, del tamaño que elijas con un deslizador (sin nombre, igual
  de alto que de ancho: desde pequeños hasta grandes), con una vista
  previa en el diálogo. Desmontar, ⋮, «Versiones de PHP…» y Arrancar o
  Parar van con el mismo estilo y el mismo tamaño que los demás.
- Al cargar un proyecto, la página sube sola hasta su visor.
- Arriba, en el recuadro de la versión: lo que gastan Nexum y sus
  servicios juntos (la ventana, LAMPP, Docker sin root con sus
  contenedores, Mailpit y el túnel), en % de la CPU de todo el equipo
  y de su RAM. Al pasar el ratón, cada parte con sus MB.
- Docker: se pueden parar todos los contenedores de Nexum a mano,
  también la MariaDB común, el Apache de Docker, su phpMyAdmin y los
  PHP de cada versión (antes sus botones no se podían pulsar). La fila
  de una MariaDB común y la del Apache de Docker tienen su Parar o
  Arrancar, y arriba hay un «Parar todos» (los de otros programas no
  se tocan). Si lo que paras es común y lo usa un proyecto en marcha,
  avisa de cuáles se quedan sin él antes de pararlo.
- Docker: al parar un proyecto del Apache de Docker, lo común que ya
  no usa nadie se para también (su MariaDB y, si no queda ninguno en
  marcha, el Apache de Docker). En la terminal: docker-parar-todo.

1.56.1 (27 oct 2026)
- Botones del proyecto a tu gusto: cuáles se ven, en qué orden y cómo
  (con su nombre, solo el icono o grandes, cuadrados con el icono y el
  nombre). En el menú ⋮ del proyecto, «Personalizar los botones…», y
  en Configuración, Visor de los proyectos. Vale para el visor del
  proyecto cargado y para el de Docker. Por defecto, «Compartir» va
  detrás de «Docker» y antes de «Log».
- Actualizaciones: se buscan al abrir la ventana la primera vez de
  cada día y, después, cada 4 veces que la abres. Si dices que no a
  una versión, se vuelve a ofrecer la próxima vez que toque buscar.
- Novedades: las direcciones como https://pma.docker.local ya no salen
  partidas.

1.56.0 (27 oct 2026)
- Docker con su propio Apache: los proyectos de Docker ya no necesitan
  LAMPP (funcionan con LAMPP parado o con cualquier versión activa). Un
  Apache en un contenedor, en otra dirección de este equipo (127.0.0.2,
  nunca abierta a la red), con las mismas reglas de seguridad que LAMPP
  (los ficheros que no se sirven y la barrera entre webs) y los .htaccess
  de cada proyecto. Las imágenes de PHP son las de siempre: ninguna más.
- Docker, varias versiones de PHP a la vez: con la misma BBDD. En un
  WordPress, cada una con su dominio (proyecto-php83.docker.local); una
  tienda PrestaShop guarda su dominio en la BBDD, así que va con uno
  (proyecto.docker.local) y la versión que elijas, con un clic. Botón
  «Versiones de PHP…» del proyecto: añadir, quitar y elegir.
- Docker, BBDD: una MariaDB común por versión de MariaDB, cada proyecto
  con su BBDD y su usuario, y un solo phpMyAdmin en
  https://pma.docker.local (con su pantalla de acceso). Un certificado
  propio para *.docker.local (solo vale para esos dominios) que Chrome y
  Firefox aceptan sin aviso.
- Configuración, Docker: la dirección y los puertos del Apache de Docker
  (80 y 443; con otros, las direcciones llevan el puerto), «Permitir»
  para que Docker sin root use los de menos de 1024 (pide la contraseña
  una vez) y «Confiar» en el certificado.
- Los proyectos que ya estaban en Docker siguen igual (con LAMPP
  delante) hasta que pulses «Pasar al Apache de Docker»: se guarda antes
  una copia de su BBDD en ~/lvm-copias y se carga en la MariaDB común.
- En la terminal: docker-nuevo, docker-php-añadir, docker-php-quitar,
  docker-php-elegir, docker-pasar y docker-web.
- Túnel de Cloudflare: «Compartir» en el visor del proyecto (y en el
  de Docker) enseña la web a un cliente o a un compañero con una
  dirección https://….trycloudflare.com, sin cuenta de Cloudflare y
  sin abrir puertos. Con contraseña (al azar, para copiar y mandar),
  el panel de administración bloqueado (tus BBDD llevan el
  administrador de pruebas) y phpMyAdmin y lo de LAMPP siempre
  bloqueados, y se cierra solo (2 h; de 1 a 12 en Configuración). La
  web no se toca: su dominio local se cambia por el del túnel al pasar.
  cloudflared se descarga de GitHub la primera vez (comprobado con su
  sha256). En la terminal: tunel-abrir, tunel-cerrar y tunel-config.
- web.local sin proyecto cargado: la página lleva el logotipo y el
  nombre de Nexum Dev Stack, y dice dónde cargar uno (Proyectos,
  Cargar). Todo va dentro de la página, sin pedir nada a otra web.

1.55.14 (27 oct 2026)
- Proyectos, menú ⋮: «Borrar el proyecto…» borra el proyecto entero:
  su carpeta, sus vhosts, las líneas de sus dominios en /etc/hosts (un
  dominio real no se queda falseado) y lo que tenga en Docker. Pregunta
  si se borra también su BBDD de la versión activa (la de phpMyAdmin),
  con copia antes por defecto. Hay que escribir el nombre de la carpeta
  para confirmar. Si un paso falla no sigue: la carpeta, lo último.
  En la terminal: borrar-proyecto <carpeta> [--bd <base> --copia].
- Imágenes de producción: uploads e img no van en git, así que lo que
  falte en local se trae de la web real. En WordPress, menú ⋮
  «Imágenes de producción…» (propone el dominio de su BBDD): mientras
  esté cargado, lo que falte de wp-content/uploads se pide a la web
  real, sin descargar nada. En PrestaShop, que se ve con su dominio real
  falseado, «Descargar de producción las imágenes que faltan…»: las de
  productos, categorías y marcas que dice su BBDD, por https con DNS
  cifrado y comprobando el certificado real. Solo imágenes, vídeos y
  PDF; nunca un .php ni fuera de img. En Dominios y hosts, cada .local
  tiene también su botón de imagen. En la terminal: media-produccion,
  media-proyecto y ps-imagenes.
- Docker: al crear un proyecto o montarlo desde Proyectos, los
  desplegables y el dominio enseñan el nombre entero.

1.55.13 (27 oct 2026)
- Cancelar ya no deja nada a medias: desde la ventana, lo que cambia
  algo pide la contraseña de administrador al empezar, no a mitad. Si se
  cancela, no se ha hecho nada. Antes, al desmontar el proyecto y cancelar
  la contraseña, se desmontaba igual. Desmontar es ahora todo o nada,
  como cargar: si un paso falla, el proyecto sigue cargado.
- Cabecera: «Dev Stack» vuelve a la letra de antes.
- Acerca de: más corto («Herramientas de desarrollo web en local») y
  una firma más corta.

1.55.12 (27 oct 2026)
- Proyectos: columna «Tamaño», con lo que ocupa cada proyecto en el
  disco (se mide en segundo plano, de 10 en 10, y cada uno se vuelve a
  medir cada 6 horas). La columna Proyecto, con el nombre entero de la
  carpeta. La etiqueta de Docker de Versiones, con su logotipo.
- Cabecera: «NEXUM» en mayúsculas y en Goldman (Google Fonts, licencia
  SIL Open Font License; va dentro del programa).

1.55.11 (26 oct 2026)
- Bases de datos: tarjeta nueva «Ocupan las BBDD», con lo que ocupan las
  de todas las versiones y una barra del disco con lo que queda libre.
- Proyecto cargado: «Añadir entorno» pasa a un botón + a la izquierda del
  entorno, en su misma fila. Sin el botón «Importar SQL»: para importar,
  la pestaña Bases de datos (o el menú ⋮ de la fila del proyecto).

1.55.10 (26 oct 2026)
- PrestaShop 1.7+ en Docker y en LAMPP a la vez: la tienda ya no deja de
  funcionar en LAMPP (error 500, «Link to database cannot be
  established») después de abrirla en Docker. Su caché (var/cache), que
  guarda la BBDD, va en Docker en un volumen del contenedor; y al cargarla,
  una caché con otra BBDD (la de Docker o la de producción) se aparta a
  ~/lvm-copias y se rehace sola.

1.55.9 (26 oct 2026)
- Docker: cada proyecto, al desplegar su fila, tiene su visor, como el del
  proyecto cargado: su nombre, versiones, dominio y si está en marcha, con
  «Abrir web», «Panel», «phpMyAdmin», «VS Code», «Log» (los errores de su
  PHP) y Arrancar o Parar. Parado, la web, el panel y phpMyAdmin se
  apagan.
- Docker, Panel: entra en el WordPress o la tienda PrestaShop del
  contenedor con el administrador de pruebas ya escrito (local@local.test,
  contraseña local). Se pone en su BBDD al crearlo con una copia y, si
  falta, al pulsar Panel (lvm-instalador docker-usuario-pruebas <nombre>).
  Las copias que salen de LAMPP siguen sin él.
- Docker, phpMyAdmin: al pulsarlo se copia la contraseña de root.
- En la lista de proyectos, «Montar en Docker» en la fila de los que tienen
  contenedores.
- Tema claro: texto blanco sobre el azul al pasar el ratón.

1.55.8 (26 oct 2026)
- Proyecto cargado: «Añadir entorno…» e «Importar SQL» pasan al recuadro
  del entorno y la BBDD; la fila de abajo queda para los accesos directos
  del proyecto, con ⋮ a la derecha. El logotipo de WordPress o PrestaShop,
  sin recuadro. Sin la explicación debajo de «Proyectos».

1.55.7 (26 oct 2026)
- Proyecto cargado: botón «Log» junto a sus botones, con el final del
  registro de errores de su web (el de su vhost), para ver al momento por
  qué da un error 500.

1.55.6 (26 oct 2026)
- Al abrir el programa busca solo si hay una versión nueva y la ofrece. Si
  se dice que no, no vuelve a preguntar por esa versión al abrirlo (solo
  avisa); sigue en el menú, Buscar actualizaciones.
- Proyectos: arriba se queda siempre el proyecto cargado, con sus botones;
  pulsar otro en la lista solo lo marca. Cada fila, al pasar el ratón,
  tiene «Cargar» y un menú ⋮ (añadir entorno en otra versión o en Docker,
  importar SQL, vincular sus BBDD, abrir la carpeta…).
- Tema claro: «Encendidos» en azul (el verde no se veía sobre el gris).
- Docker: el aviso del Docker de Ubuntu (el que va como administrador)
  explica qué es y por qué conviene apagarlo.

1.55.5 (26 oct 2026)
- Copiar una BBDD a una versión con un MariaDB antiguo (como de la 8.2 a la
  7.4) ya no falla con «Unknown command '\-'»: la descarga lleva una sola
  línea del modo sandbox y la carga las quita todas.

1.55.4 (26 oct 2026)
- Interruptores que piden la contraseña de administrador (barrera entre
  webs, correo de pruebas y su modo de WordPress, los .local de Dominios y
  hosts): si se cancela, no cambia nada y el interruptor vuelve a su sitio.
  Si no se puede aplicar, se deja como estaba.
- Proyectos: el asistente de proyecto nuevo (clonar de git, con su versión
  y su BBDD) se abre con el botón azul «Nuevo proyecto…» de la lista.

1.55.3 (25 oct 2026)
- Cargar un proyecto es todo o nada: la contraseña se pide antes de cambiar
  nada y, si se cancela o falla un paso, se queda el proyecto que había
  (el enlace del vhost, la versión activa y Apache, como estaban). Antes
  podía quedar a medias: cargado en la ventana y la web sin estilos.

1.55.2 (25 oct 2026)
- Al cargar un proyecto, el visor pasa a él en cuanto termina la carga, con
  sus botones, sin esperar a volver a leer todo. Elegir un proyecto de la
  lista es instantáneo (antes se rehacía la lista entera).

1.55.1 (25 oct 2026)
- Mailpit: se instala aunque el paquete cambie de forma; si no se puede,
  dice por qué y desde dónde descargarlo a mano.

1.55.0 (25 oct 2026)
- Correo de pruebas con Mailpit: lo que mandan las webs de este equipo
  (formularios, pedidos, contraseñas) no llega a nadie, se ve en su
  bandeja (botón Correo, arriba, con los correos sin leer). Encendido por
  defecto; se apaga en Configuración. Mailpit arranca y para con la
  versión activa, con tu usuario y solo en 127.0.0.1.
- Mailpit se instala desde Configuración: la versión oficial de GitHub,
  comprobada con su sha256 y de root en /opt/config/mailpit.
- PHP de todas las versiones: mail() va a Mailpit. PrestaShop: al cargar
  la tienda, su correo va por SMTP a Mailpit (en todas sus tiendas).
- WordPress con plugins de SMTP o Brevo, en Configuración: llevarlos a
  Mailpit (por defecto: WP Mail SMTP, Easy WP SMTP y los de SMTP siguen,
  con su correo a Mailpit; Brevo, FluentSMTP, Post SMTP y los que mandan
  por una API se desactivan en la copia local), desactivarlos todos o no
  tocarlos (avisa: su correo puede llegar de verdad).
- Lo que se cambia en las BBDD para el correo no va en las copias
  (exportar-bd, copiar-bd, Docker): llevan el correo de producción. Al
  apagarlo o elegir «No tocarlos», se deshace al cargar el proyecto.
- En la terminal: lvm-instalador correo (estado, si, no, wordpress
  mailpit|desactivar|nada, instalar, vaciar y bd <base>).
- Docker: sus proyectos aún no mandan a Mailpit.
- La versión del programa va arriba, detrás de «Entornos LAMPP y Docker»
  (abajo de la barra lateral ya no va la firma: está en Acerca de).
- Versiones de PHP: una versión vulnerable ya no sale también como
  «Actualizada», y los tres puntos ya no enseñan «Más» al pasar el ratón.

1.54.3 (25 oct 2026)
- Al instalar o actualizar vuelve a salir la lista de pasos (se quedaba
  vacía), cada uno con su logotipo: Apache, PHP, Perl, ProFTPD, MariaDB y
  phpMyAdmin.
- Arriba ya no está el botón de phpMyAdmin: sigue en la pestaña Bases de
  datos.
- En el título, «Dev Stack» va sin negrita y en azul.
- Bases de datos y Docker: al entrar en la pestaña, todas las versiones y
  los proyectos aparecen plegados; se despliega uno a la vez.

1.54.2 (24 oct 2026)
- Proyecto cargado: botón Docker, junto a Panel. Si no hay Docker, ofrece
  instalarlo; si el proyecto no está en Docker, lo monta con la versión
  de PHP que elijas (descarga las imágenes que falten); si ya lo está, lo
  arranca y, con varias versiones, pregunta cuál. Un proyecto puede estar
  en Docker con varias versiones de PHP (docker-crear … --nombre).
- Diálogos con el texto centrado y más corto, y el botón principal dice lo
  que hace («Borrar la BBDD», «Actualizar a PHP 8.4.27»…).
- Arriba, los avisos a la izquierda del visor y el menú a su derecha.
- Versiones de PHP: «Actualizado» en verde. Bases de datos: una sola
  versión desplegada a la vez y botones de acciones con separación.
- Docker: columna ID de cada contenedor (en lugar de Estado) y, primero en
  la fila del proyecto, arrancar o parar todos sus servicios a la vez.
- Docker, Imágenes: imagen, etiqueta e ID por separado, y botones para
  volver a descargarla de Docker Hub o borrarla (si no la usa ningún
  contenedor). Volúmenes: botón para borrar los que no use ninguno. En la
  terminal: docker-imagenes borrar|descargar <imagen> y
  docker-volumen-borrar <volumen>.

1.54.1 (24 oct 2026)
- PHP2Shell (CVE-2026-109618 y CVE-2026-109619): en Versiones de PHP,
  las que no tienen el arreglo salen en rojo («Vulnerable (PHP2Shell)»)
  y activarlas lo pregunta. Lo tienen 8.2.35, 8.3.36, 8.4.27 y 8.5.12
  o posteriores; los XAMPP no se pueden arreglar.
- PHP 7.4.33, 8.0.30 y 8.1.34 se compilan con el parche de seguridad
  que publicó el equipo de PHP (no es una versión nueva: se ven como
  «7.4.33 + parche de seguridad»).
- «Actualizar a PHP X.Y.Z» en el menú ⋮ de las versiones con un parche
  concreto (lampp-8.3.10) y de los XAMPP: instala la nueva al lado, le
  copia las BBDD con sus vínculos y, si era la activa, la activa. La de
  antes se queda hasta que la desinstales. En la terminal:
  lvm-instalador actualizar-a <versión> <php>.
- Ya no se ofrece el XAMPP 8.2.4.
- En todas las versiones y en Docker, el php.ini con las mitigaciones de
  PHP2Shell: sin el progreso de las subidas en la sesión, poco
  anidamiento en los formularios y 64 MB como mucho por petición.
  PHP-FPM renueva sus procesos cada 50 peticiones.
- Barrera entre webs para todos los proyectos: otra web abierta en el
  navegador no puede mandarles formularios ni peticiones. Se apaga en
  Configuración (o lvm-instalador barrera-web no) para probar una
  pasarela de pago que vuelve con un POST.
- Sin CGI ni SSI en las carpetas de los proyectos.
- Las descargas de PHP, Apache, APR, MariaDB y phpMyAdmin se comprueban
  también con la firma de quien las publica.
- Las pilas propias se compilan con un usuario del sistema
  (nexum-build): nada de tu usuario puede cambiar lo que root copia.
- La BBDD descargada ya no lleva el administrador de pruebas
  (local@local.test); la de trabajo no cambia.
- Docker: el phpMyAdmin de cada proyecto pide usuario y contraseña (la
  copia el botón de la llave); «Actualizar imagen» rehace su PHP con lo
  último de Docker Hub. Docker va sin la terminal y con su propia
  configuración, y la contraseña de la BBDD no sale en las órdenes.

1.54.0 (24 oct 2026)
- Nuevo nombre: Nexum Dev Stack, con logotipo nuevo (en el menú de
  aplicaciones, en la ventana y en el paquete). Los comandos
  (lvm-instalador, lvm) y las carpetas no cambian.
- Ventana nueva: cambian la organización y el aspecto, con las mismas
  órdenes de siempre. Arriba, siempre a la vista, el visor de la versión
  montada (PHP, Apache y MariaDB con su punto, encender o apagar y sus
  servicios), el menú, Localhost, phpMyAdmin y los avisos en un solo
  botón. En Proyectos, el cargado en grande con su entorno (versión de
  PHP), su BBDD y sus botones, y la lista de todos, que busca por el
  nombre de la carpeta o de su BBDD. Versiones de PHP con su soporte y su
  último parche (los componentes, en un diálogo), Bases de datos y Docker
  en tablas por versión y por proyecto, con sus tarjetas arriba, y tema
  claro u oscuro en el menú. Los diálogos, con el mismo aspecto y en azul.
- Bases de datos: el tamaño de cada BBDD (datos e índices) y el total de
  cada versión. Se mide con su versión activa y en marcha, y se recuerda.
- Tareas: barra más gruesa con el porcentaje y lo que queda siempre a la
  vista, y el registro como una terminal: una descarga es una línea con
  su porcentaje que avanza, no una línea por cada paso.
- Versiones de PHP: Actualizar solo sale cuando hay un parche más nuevo,
  y si ya está al día lo dice.
- Docker: los contenedores ya no arrancan solos al encender el equipo
  (se arrancan desde la pestaña Docker); los que ya había se cambian
  solos. CPU y memoria de los contenedores, sus imágenes y volúmenes, y
  acciones para cada contenedor, también borrarlo. En la terminal:
  lvm-instalador docker-contenedor arrancar|parar|reiniciar|registros|
  borrar <contenedor>.
1.53.0 (23 oct 2026)
- Nueva pestaña Docker: proyectos con cualquier versión de PHP (de la 5.6
  a la 8.5, también 7.1 o 7.4) en contenedores, a la vez que LAMPP. Cada
  uno lleva su PHP, su MariaDB con una copia de su BBDD de LAMPP y su
  phpMyAdmin, y se abre por su dominio (carpeta.docker.local, con https)
  desde el Apache de la versión activa, con sus .htaccess de siempre. Su
  wp-config.php (o la configuración de PrestaShop) se sustituye solo
  dentro del contenedor, así que la carpeta se puede seguir usando con
  LAMPP. Arrancar, parar, ver registros y borrar desde la pestaña.
- Docker, cambiar de PHP: el botón con la versión de cada proyecto la
  cambia sin borrarlo (solo cambia su contenedor de PHP; su BBDD y su
  configuración se quedan). Si con la nueva no arranca, vuelve a la de
  antes. Así se prueba un proyecto con 7.4, 8.1, 8.2... uno tras otro. En
  la terminal: lvm-instalador docker-php <nombre> <versión>.
- Docker, consola: arriba de la pestaña, como en Docker Desktop, todos los
  contenedores con su imagen, si están en marcha (y desde cuándo) y sus
  puertos.
- Docker se instala desde la pestaña en modo sin root: los contenedores
  corren con tu usuario y el Docker del sistema (con root) se deja
  apagado, así que ni un proyecto ni Docker pueden hacerse
  administradores del equipo. En la terminal: lvm-instalador
  docker-instalar, docker-crear <carpeta> <php> <mariadb> [--bd <base>
  --desde <versión>], docker-arrancar|docker-parar|docker-registros|
  docker-borrar <nombre>.
1.52.0 (23 oct 2026)
- Cargar proyecto: botón Replicar, junto a «Montar nuevo proyecto», para
  llevar un proyecto a otra versión de PHP. Se elige el proyecto, de qué
  versión se copia su BBDD, a cuál, el nombre que tendrá allí (se
  propone el de esa versión: wp_tienda_8_4 → wp_tienda_8_5; si ya hay
  una con ese nombre, se avisa de que se sustituye) y la carpeta con la
  que se cargará en ella. En la terminal: copiar-bd <base> <origen>
  <destino> --como <nombre> --carpeta <carpeta|->.
- Cargar proyecto: cada versión de PHP puede ir con su propia carpeta.
  Las BBDD quedan vinculadas a la carpeta del proyecto en cada versión,
  no en todas a la vez, así que la copia de una BBDD en la 8.5 puede ir
  con una carpeta distinta de la de la 8.4. Con el botón de vincular de
  cada proyecto se elige su BBDD en cada versión, o «Ninguna» para
  desvincularla; los botones del proyecto cargado (phpMyAdmin, panel)
  usan la de la versión activa. En la terminal: lvm-instalador
  vincular-bd <base> <versión> <carpeta|->.
- BBDD, copiar: el botón de cada BBDD la copia, con el mismo nombre, de
  esa versión a la que elijas, y siempre avisa antes de hacerlo (y de si
  la sustituye). Para copiarla con otro nombre o con otra carpeta está
  Replicar.
- BBDD por versión: en la versión activa, la BBDD que usa el proyecto
  cargado lleva un punto verde.
- Versiones: junto a cada versión de PHP instalada sale la fecha en que
  se publicó.
- Versiones: «Instaladas» e «Instalar nuevas versiones de PHP» se pliegan
  y se despliegan al pulsar su título (plegadas, dicen cuántas hay), y
  siguen así al volver a abrir la ventana.
- Versión activa: los botones de arrancar, reiniciar y parar son más
  grandes.
- Instalar: cada versión nueva de PHP va en una carpeta con su versión
  completa (/opt/lampp-8.4.27), también la última de cada rama, que
  antes iba en /opt/lampp-8.4. Las que ya estaban no cambian de nombre.
1.50.1 (22 oct 2026)
- Pestaña Hosts: los dominios .local de los vhosts se pueden apagar. Su
  interruptor estaba bloqueado: el gestor los mantiene siempre en
  /etc/hosts (sin su línea, el equipo los pregunta a la red y cualquiera
  de la misma wifi podría contestar) y volvía a añadirlos aunque se
  quitaran a mano. Ahora, al apagar uno (se avisa antes), su línea
  queda comentada y se recuerda que está apagado, así que no se vuelve a
  añadir; al encenderlo, vuelve a mantenerse. En la terminal:
  lvm-instalador hosts-falsear <dominio>.local si|no.
- Pestaña Hosts: los .local ya no salen como «Host falseado» (no hay
  ninguna web real a la que lleven): van en «Dominios de los vhosts».
1.50.0 (22 oct 2026)
- Buscar actualizaciones: busca la versión nueva en GitHub, en las
  publicaciones del repositorio de Nexum Stack, y ya no hace falta
  dejar el .deb en Descargas. Si hay una más nueva, la descarga a
  ~/.lvm-instalador/actualizaciones, enseña su fecha y su huella y la
  instala al poner la contraseña. Sin conexión se sigue buscando en
  Descargas.
- Seguridad: cada versión va firmada por quien publica el programa. Se
  comprueba la firma antes de ofrecerla y otra vez como administrador
  antes de instalarla, con la clave que trae el paquete
  (/opt/lvm-instalador/nexum-stack-firma.gpg); sin firma válida no se
  instala nada desde la ventana. Tampoco se instala una versión más
  vieja que la que tienes, aunque esté firmada.
  * Esta versión se instala una vez en la terminal (sudo apt install):
    cambian su ayudante y sus dependencias (gpgv).
- Herramientas: «Icono en el menú de aplicaciones» decía todavía
  «LAMPP Version Manager».
1.49.0 (22 oct 2026)
- Nuevo nombre: Nexum Stack (antes LAMPP Version Manager). Cambian el
  título de la ventana, el nombre del icono del menú y los textos; los
  comandos (lvm-instalador, lvm), las carpetas y el funcionamiento siguen
  igual.
  * Esta versión se instala una vez en la terminal (sudo apt install):
    cambian los textos de su ayudante y de la ventana de la contraseña.
1.48.0 (22 oct 2026)
- Subir o actualizar una BBDD: si la base ya existe, ahora siempre se
  borran todas sus tablas antes de cargar la copia (antes era una opción,
  «Vaciar la BBDD antes de cargar», que venía apagada). Sin vaciarla, las
  tablas que la copia ya no trae se quedaban, y una copia de phpMyAdmin
  (no lleva DROP TABLE) cargada otra vez tras un error sumaba sus filas a
  las de antes: así se repitieron filas y faltaron claves primarias en una
  base de WordPress. Si la base tiene tablas, antes se guarda una copia
  suya en ~/lvm-copias (…-antes-de-cargar-fecha.sql.gz); si no se puede
  guardar, no se toca nada, y si la carga falla, se dice dónde está.
  Copiar una BBDD a otra versión que ya la tiene sigue igual (ya guardaba
  su copia). En la terminal: importar-bd <fichero> <base> [--crear]
  [--sin-copia]; --vaciar se sigue admitiendo, pero ya no hace falta.
1.47.0 (22 oct 2026)
- Tiendas con dominio real (las falseadas en /etc/hosts): el navegador ya
  no avisa con «La conexión no es privada» mientras están falseadas, así
  que Claude in Chrome también puede abrirlas. Al falsear una, Chrome,
  Chromium y Firefox aceptan su certificado propio; al dejar de
  falsearla (o al cargar otro proyecto), dejan de aceptarlo. Así, con su
  clave (Apache la tiene en memoria) no se puede suplantar la web de
  verdad: mientras está falseada, el navegador no va a ella. Si cambias
  /etc/hosts a mano, sale el aviso «El navegador acepta webs reales que
  ya no están falseadas» con el botón Quitar. En la terminal:
  lvm-instalador confiar-certificados --quitar.
- Prefijo de las tablas al rehacer wp-config.php: siempre uno que traen
  las tablas de la base (las tablas nunca se cambian ni se renombran).
  Si la base tiene tablas de varios WordPress, se usa el del wp-config.php
  del proyecto (antes ganaba el de la copia de este equipo) y, si ninguno
  está en la base, ya no se escribe un prefijo sin tablas: no se toca y
  se avisa. En las tiendas con varios prefijos, el que ya usaba su
  configuración si la base lo tiene.
1.46.0 (22 oct 2026)
- Certificados de los proyectos: el navegador ya no avisa con «La conexión
  no es privada». Desde que Arreglarlos quitó la CA común, cada proyecto
  https lleva su propio certificado y Chrome avisaba en todos; con el
  aviso, las herramientas que manejan el navegador (como Claude in
  Chrome) no podían abrirlos. Ahora Chrome, Chromium y Firefox aceptan el
  certificado de cada proyecto con un dominio de pruebas (web.local,
  .local, .test), solo ese y solo para su dominio (no una CA: no vale
  para ninguna otra web). Los de un dominio real (las tiendas falseadas
  en /etc/hosts) siguen avisando: Apache tiene su clave en memoria, donde
  la puede leer el PHP de cualquier web, y con ella se podría suplantar
  la web de verdad. Se hace solo al arreglar los certificados y al crear el
  vhost de un proyecto o una tienda; para los que ya estaban, sale el
  aviso «El navegador avisa al abrir estos proyectos» con el botón
  Confiar. Después cierra el navegador y vuelve a abrirlo. En la
  terminal: lvm-instalador confiar-certificados [dominio].
1.45.1 (22 oct 2026)
- BBDD, copiar a otra versión: ahora salen también las versiones que ya
  tienen esa BBDD, marcadas «ya la tiene: se sustituye». Al elegir una, se
  pide confirmación, se guarda antes una copia de la suya en ~/lvm-copias
  y se pone en su lugar la de origen (por ejemplo, para volver a copiar a
  la 8.4 una BBDD que ya se había copiado antes desde la 8.2.4). En la
  terminal: copiar-bd <base> <origen> <destino> --sustituir.
1.45.0 (22 oct 2026)
- Administrador de pruebas en los paneles: al cargar una BBDD de
  WordPress o PrestaShop se le añade un administrador local@local.test
  con contraseña local (el mismo en todos los equipos; las BBDD de este equipo
  nunca van a producción). En Cargar proyecto, el botón del panel abre
  una página con los dos ya escritos: solo hay que pulsar Entrar. Con
  las BBDD que ya estaban cargadas, se crea al pulsar el botón. En la
  terminal: lvm-instalador usuario-pruebas <base> [carpeta].
- Seguridad (noveno repaso):
  * El cliente de MariaDB y mysqldump de XAMPP ya no leen ~/.my.cnf:
    cualquier programa tuyo podía prepararlo para que cargaran una
    biblioteca suya con el permiso de administrador que la tarea ya tenía.
    Por lo mismo, git, ssh, certutil y curl van sin tu configuración o
    fuera de la terminal de la tarea.
  * La contraseña de administrador solo se manda a un sudo de verdad de
    la tarea: un programa que escribiera la marca de sudo ya no hace salir
    el cuadro de la contraseña.
  * Editar /etc/hosts: una línea con un retorno de carro (CR) en medio se
    saltaba la comprobación y podía llevar cualquier dominio a otra IP.
  * Montar nuevo proyecto: el dominio de una tienda (el de su base) ya no
    se falsea solo, porque la base y el nombre de la carpeta vienen con el
    repositorio. Si es el suyo, se crea en la pestaña Hosts (Nuevo
    proyecto con dominio falseado). Por SSH solo se clona de servidores
    cuya clave ya conoces (y de GitHub, GitLab y Bitbucket), y sin git-lfs.
  * Un Listen abierto a la red en los vhosts compartidos ya no pasa sin
    aviso: la versión no se arranca hasta quitarlo (Editar vhosts).
  * Tampoco se sirven por la web las exportaciones de clientes de WP All
    Import (carpeta wpallimport), las de PrestaShop en .zip o .xml, ni
    .my.cnf, .netrc, .pgpass, credentials*.json, .aws o .docker.
  * Otros: PHP_TIMEZONE, el correo de git en ServerAdmin y
    importar-bd --proyecto se comprueban antes de usarlos; los nombres solo
    admiten letras sin tilde (como en la ventana) aunque el equipo esté en
    español; las versiones de php.net se validan antes de enseñarlas.
  * El script lampp de las versiones propias solo cierra el MariaDB de su
    .pid (lo escribe mysql) y los vhosts de versiones antiguas pasan al
    administrador sin seguir enlaces.
- Actualizar desde la ventana: si la versión nueva hay que instalarla una
  vez en la terminal (cambia el programa que instala las actualizaciones),
  ya no sale el error de dpkg («Tubería rota»): se explica y hay un botón
  para copiar la orden (sudo apt install …).

1.44.2 (22 oct 2026)
- Seguridad:
  * ~/lvm-copias (copias de BBDD de clientes, vhosts y /etc/hosts
    anteriores) es siempre solo tuya, aunque ya existiera con otros
    permisos. Las copias que se descargan con exportar-bd, también.
  * Vaciar la base antes de cargar: si el volcado no se puede cargar
    (motores FEDERATED, CONNECT o SPIDER activos), ya no se borra antes.
  * Pestaña Hosts: los .local ya no se apagan (no existen fuera y, sin su
    línea, el equipo los preguntaba a la red, donde cualquiera de la misma
    wifi podía contestar). Los que estaban apagados vuelven a encenderse.
  * La contraseña temporal del usuario de la BBDD ya no se ve con ps
    mientras se carga un volcado.

1.44.1 (21 oct 2026)
- Versiones, Instalar: la fecha de publicación va junto a la versión de
  PHP, y «Parche de seguridad» es solo texto azul (sin fondo).
- Cargar proyecto: el título va fuera del recuadro, como en los demás
  apartados; el recuadro tiene más aire arriba y abajo, y el buscador y
  «Montar nuevo proyecto» van más separados de los botones del proyecto.
- Otro parche: la ventana es más ancha (la versión ya no sale cortada).

1.44.0 (21 oct 2026)
- Seguridad (octavo repaso):
  * Cerrar procesos: un programa que se pusiera un nombre trucado podía
    hacer que el gestor cerrara como administrador otros procesos, o todos
    los del equipo. Ahora los nombres se limpian y solo se cierran números
    de proceso de verdad.
  * Copiar una BBDD a otra versión: el programa auxiliar del cliente de
    MariaDB estaba en tu carpeta, y otro programa tuyo podía cambiarlo y
    conseguir permisos de administrador. Ahora va en una carpeta del
    administrador. Si se cancela la copia, no queda el volcado temporal.
  * Subir un volcado: sus vistas y funciones «SQL SECURITY INVOKER» se
    cargan ya como «DEFINER», así que, aunque la web o phpMyAdmin las lean
    a mitad de la carga, no se ejecutan como root. Al acabar, el usuario
    de la BBDD se vuelve a crear con permisos solo sobre su BBDD.
  * El MariaDB temporal (copiar o descargar una BBDD de otra versión)
    nunca se arranca como administrador.
  * Si no se puede dejar una versión solo para este equipo, ya no se
    arranca (al cargar un proyecto, Servicios, Arrancar o Reiniciar).
  * Actualizar desde la ventana: el ayudante ya no deja que apt instale
    otros paquetes «recomendados» o «sugeridos». Por eso esta versión se
    instala una vez en la terminal: sudo apt install
    ~/Descargas/lvm-instalador_1.44.0_all.deb (las siguientes, otra vez
    desde la ventana).
- Versiones, Instalar: cada versión de PHP lleva la fecha en que se
  publicó y si es un parche de seguridad (según php.net) o solo de errores.
- Cargar proyecto: solo dice a dónde apunta web.local (sin «Cargado
  ahora:», para que quepa el nombre entero) y, junto al nombre, un botón
  para desmontar el proyecto (web.local enseña una página vacía). Los botones van, de
  derecha a izquierda, en este orden: VS Code, phpMyAdmin, wp-admin y
  web.local, y son algo más grandes. Si la versión montada no tiene la
  BBDD del proyecto cargado, sale un aviso en rojo.
- Montar nuevo proyecto: botón junto al buscador de proyectos. Se
  despliega un asistente de tres pasos: la dirección del repositorio de
  GitHub (se clona en htdocs), la versión de PHP y la BBDD nueva, con su
  volcado si lo hay. Al terminar, el proyecto queda cargado. En la
  terminal: lvm-instalador montar-proyecto <url> <carpeta> <version> <base>
  [volcado] y lvm-instalador desmontar-proyecto.
- Los mensajes que salen al dejar el ratón encima tienen el aspecto de la
  ventana: gris oscuro y con las esquinas redondeadas.
- Herramientas, Registro de errores: ya no enseña el último error.
- Comandos: cada uno en su línea, con lo que hace debajo, separados por
  secciones resaltadas.
- Novedades: más espacio entre versiones, puntos y líneas.

1.43.1 (21 oct 2026)
- Herramientas, Registro de errores: primero el registro del vhost del
  proyecto cargado (web.local-error_log), que es donde van los errores de
  PHP de la web (el «error crítico» de WordPress) con PHP-FPM. Se ve el
  último error de PHP resumido: el mensaje, el fichero y la línea. Debajo,
  el general de Apache. «Ver el final» separa en líneas los mensajes de
  PHP-FPM, que llegan todos en una.

1.43.0 (21 oct 2026)
- BBDD: botón para copiar una BBDD a otra versión de PHP que no la tenga,
  para probar si el proyecto funciona con ese PHP. Se elige la versión en
  una ventana; la de origen no se toca. Si la de destino no es la activa,
  se arranca su MariaDB solo para la copia (pide la contraseña). La copia
  se carga igual de protegida que al subir un volcado. Después, al cargar
  el proyecto, se pregunta en qué versión. En la terminal:
  lvm-instalador copiar-bd <base> <origen> <destino>

1.42.3 (21 oct 2026)
- Cargar proyecto con la BBDD en varias versiones: la pregunta es más corta
  y cabe en una línea («¿Qué versión del proyecto y de PHP quieres?»).
- La versión elegida va solo con el borde verde de su tarjeta (ya no sale
  también el recuadro del botón de radio).

1.42.2 (21 oct 2026)
- Pestaña Hosts: aviso «web.local no lleva a este equipo» con el botón
  Arreglarlo, si en /etc/hosts web.local apunta a otra dirección (como
  127.0.1.1, la del nombre del equipo en Ubuntu) o no está. Apache solo
  escucha en 127.0.0.1 y el navegador daba «No se puede acceder a este
  sitio web» (ERR_CONNECTION_REFUSED). Se arregla una sola vez.
- phpMyAdmin abierto por localhost (un marcador antiguo o la costumbre
  de XAMPP) ya no da el aviso de error: lleva directamente a su dirección
  buena, 127.0.0.1/phpmyadmin. Por web.local u otro dominio sigue dando el
  aviso. Pulsa Protegerlas para aplicarlo a las versiones instaladas.

1.42.1 (21 oct 2026)
- Cargar proyecto: el proyecto cargado tiene ahora cuatro botones de icono,
  todos del mismo tamaño (al dejar el ratón encima se ve qué abre cada uno):
  * Bola del mundo: el proyecto en el navegador (web.local). Sustituye al
    botón verde «Abrir web.local».
  * phpMyAdmin: su BBDD directamente.
  * WordPress o PrestaShop: su panel de administración (wp-admin, o el
    back office de la tienda, se llame como se llame su carpeta).
  * Visual Studio Code, como antes.

1.42.0 (21 oct 2026)
- Nuevo aviso en Versiones: «Tablas del sistema de MariaDB antiguas». Las
  de algunas versiones vienen de una MariaDB anterior y el servidor llena
  su registro de errores (en una 8.2.4 llegó a 28 GB). Repararlas las pone
  al día sin tocar las BBDD de los proyectos (copia antes en ~/lvm-copias)
  y vacía el registro si es grande.
- Registrar un XAMPP de /opt/lampp ya no borra su htdocs si tiene proyectos
  (se aparta en /opt/htdocs-de-lampp-...) y guarda sus vhosts en ~/lvm-copias.
- Seguridad (séptimo repaso). Pulsa Protegerlas otra vez para aplicarlo:
  * Volcados: aunque se cierre la ventana a mitad de la carga, no queda
    nada INVOKER ni ningún evento; un evento que ya estuviera en marcha se
    corta, y al terminar el usuario de la BBDD ya no puede crear vistas,
    rutinas ni eventos. Root repasa la base al final. No se carga si
    MariaDB tiene activos FEDERATED, CONNECT o SPIDER.
  * Vhosts: un registro o un certificado entre comillas con espacios ya no
    puede llevar a otra carpeta (Apache lo abre como root). Los
    certificados nuevos, solo de las carpetas del gestor (los que ya
    tenías siguen valiendo), y los registros no pueden llamarse como sus
    ficheros de control.
  * Los dominios .local de los vhosts van siempre en hosts (si no, el equipo
    los pregunta a la red y otro de la misma wifi podría contestar).
  * Protegerlas y Cargar proyecto quitan la escritura para cualquier
    usuario en htdocs (plugins que dejan carpetas en 777).
  * Más ficheros que no se sirven: claves (.pem, .key, .p12, id_rsa, la
    carpeta .ssh), bases SQLite, .ini, .conf y las exportaciones de
    clientes de PrestaShop (customers_export).
  * Un dominio guardado para un proyecto solo se falsea si tiene su vhost
    o se parece a la carpeta.
  * Una carpeta de proyecto manipulada (un FIFO) ya no cuelga la ventana.
  * El acceso del menú y el comando lvm-instalador del paquete siguen
    apuntando al script de /opt aunque se ejecute una copia de Descargas.
  * Instalar versiones rechaza enlaces duros a ficheros de otros.

1.41.0 (21 oct 2026)
- Cargar proyecto: botón con el icono de Visual Studio Code a la derecha
  de «Abrir web.local». Abre la carpeta del proyecto cargado; si ya está
  abierta en VS Code, trae su ventana delante (no abre otra).
- Seguridad (sexto repaso, tras otra auditoría). Pulsa Protegerlas en el
  aviso de Versiones para aplicarlo a las versiones ya instaladas:
  * phpMyAdmin: una web abierta en el navegador ya no puede enviarle una
    consulta (un formulario o un fetch a 127.0.0.1). Desde otra web solo
    se abre su portada; escribiendo la dirección o desde el gestor, igual
    que siempre.
  * MariaDB ya no lee ni escribe ficheros del equipo desde SQL
    (LOAD_FILE, INTO OUTFILE, LOAD DATA LOCAL): secure_file_priv en una
    carpeta vacía de cada versión (etc/lvm-sin-ficheros).
  * Más ficheros que no se sirven: registros .log, .yml (docker-compose
    lleva las claves), copias de wp-config.php y copias de seguridad de
    las webs (.wpress, Duplicator, UpdraftPlus...).
  * Instalar versiones y actualizar phpMyAdmin: lo compilado no puede
    llevar enlaces fuera de la versión, y las carpetas tmp las crea root.
  * Protegerlas prepara los ficheros como root en una carpeta de root, y
    los certificados de los proyectos los crea root.
  * Volcados: se borran los eventos programados y las tablas que guardan
    sus ficheros fuera de MariaDB (DATA DIRECTORY), y se avisa.
  * El MariaDB temporal de las copias solo se para por su propio .pid, y
    los nombres raros de un proyecto o un .zip ya no cambian lo que se ve
    en la terminal.

1.40.1 (21 oct 2026)
- Ventana: los títulos de los apartados ya no llevan icono; lo lleva cada
  fila (Virtual hosts, Hosts del sistema, error_log, Comandos, Novedades...).

1.40.0 (21 oct 2026)
- Seguridad (quinto repaso, tras otra auditoría):
  * Actualizar desde la ventana: el ayudante exige que cada fichero del
    paquete sea de root y con sus permisos (sin setuid ni escritura para
    otros) y lee los scripts de instalación sin seguir enlaces.
  * Volcados: una vista rota en el volcado ya no deja a medias el paso
    de SQL SECURITY INVOKER a DEFINER; lo que no se pueda pasar se
    borra y se avisa.
  * Certificados: los de los proyectos se guardan en /opt/config/ssl,
    no en /etc/ssl/certs (allí el sistema los daba por buenos para
    cualquier web). Nuevo aviso «Certificados en los que confía todo el
    equipo» con el botón Arreglarlos (arreglar-certificados): pone un
    certificado propio a cada proyecto https y quita la confianza a las
    CAs locales sin límite de dominios que los firmaban.
  * Los certificados se crean con tu usuario y solo en la carpeta del
    gestor (nunca donde diga un vhost). Dominios guardados validados.
  * Protegerlas corrige también lo que ya estaba abierto (Listen con la
    IP de la red, bind-address 0.0.0.0, DefaultAddress, puertos de más)
    y cambia la clave SSL de fábrica de XAMPP, igual en todos.
  * Más ficheros que no se sirven: .dump, .old, .orig, copias~,
    error_log, auth.json, .npmrc, .sql.xz y .sql.bz2.
  * Lo compilado se copia a /opt sin conservar el dueño ni el setuid.
    Root ya no sigue enlaces al escribir la configuración de un
    proyecto ni al vaciar la caché de una tienda.
  * La ventana usa los programas del sistema (no los de ~/.local/bin).
  * Al instalar no se usa la caché de descargas, y phpMyAdmin lleva
    siempre sus huellas fijadas.
  * Lo que se compila corre sin la terminal de la tarea: aunque un
    programa tuyo lo cambie, no puede usar el permiso de sudo ya dado.
  * Cerrar procesos de otras versiones: un .pid manipulado ya no hace
    que se cierre otro programa del sistema ni la versión montada.
  * Las tareas de la ventana reciben solo las variables necesarias (ni
    funciones exportadas de bash ni las de prueba del gestor).
  * Protegerlas no deja dos Listen iguales (Apache no arrancaría).
  * Una CA local solo se avisa y se quita si su clave está en tu carpeta;
    también se apartan los certificados viejos sin usar de /etc/ssl/certs
    y se crean los que falten.
  * Esta versión se instala una vez en la terminal (sudo apt install):
    su ayudante cambia.

1.39.1 (20 oct 2026)
- Ventana: «BBDD» en lugar de «base de datos» en todos los textos.

1.39.0 (20 oct 2026)
- Seguridad (cuarto repaso, tras otra auditoría):
  * La contraseña de administrador va por una terminal exclusiva: ningún
    otro programa de tu usuario puede abrirla para leerla. La ventana
    no se puede inspeccionar desde fuera.
  * Actualizar: el ayudante revisa el paquete con tarfile (sin enlaces
    ni ficheros especiales), exige la huella, que el propio ayudante y
    la acción de polkit sean los instalados y las mismas dependencias.
    /opt pasa a ser del administrador al instalar el paquete.
  * Vhosts y /etc/hosts: se leen como los lee el sistema (por bytes);
    un carácter de control como el nulo hacía que Apache viera una línea
    que la comprobación no veía.
  * Volcados: cada base tiene su usuario (lvm_bd_<base>), con el
    permiso solo para ella (el _ ya no vale por cualquier carácter),
    que se bloquea al terminar: sus disparadores y vistas siguen
    funcionando (en la 1.37 dejaban de hacerlo). Sus vistas y
    funciones SQL SECURITY INVOKER pasan a DEFINER, y el gestor solo
    lee como root tablas de verdad.
  * Reglas web sin distinguir mayúsculas (.ENV, .GIT) y más ficheros
    que no se sirven: copias .sql, debug.log, .vscode, config.inc.php.
    Una web de fuera ya no puede leer la API de tus WordPress (CORS).
  * Los wp-config.php que prepara el gestor desactivan el editor de
    plugins y temas (DISALLOW_FILE_EDIT).
  * phpMyAdmin se actualiza con huellas fijadas y solo si la versión
    es de root. El dominio de una tienda solo se falsea si su nombre
    va en la carpeta (prestashop.com ya no vale).
  * Los ficheros raros en un proyecto (FIFO, /dev/zero) ya no cuelgan
    la lista, y todos los python3 van con -I.

  * FTP de XAMPP: solo entra tu usuario. TRACE desactivado.
  * Esta versión se instala una vez en la terminal (sudo apt install):
    su ayudante y su postinst cambian.

1.38.1 (20 oct 2026)
- Barra lateral: filas más altas, como las de Configuración de Ubuntu.

1.38.0 (20 oct 2026)
- phpMyAdmin tiene su propia dirección: http://127.0.0.1/phpmyadmin/
  (los botones ya la abren). En 127.0.0.1 no hay nada más, y en
  localhost, web.local o los dominios falseados da 403. Así, un fallo
  XSS en un proyecto (que va en localhost/carpeta o en su dominio) no
  puede leer phpMyAdmin: para el navegador es otra web.
- Actualizar phpMyAdmin: botón Actualizar en su fila de cada versión y
  aviso en Versiones (Actualizarlos) cuando trae uno con fallos ya
  corregidos. Pone el más nuevo que admite su PHP (5.2.x desde PHP
  7.2.5, 5.1.4 para PHP 7.1), comprobado con su sha256, con la misma
  configuración y una clave de cookies nueva si era la de fábrica. El
  anterior queda en phpmyadmin.anterior.
  * En la terminal: lvm-instalador actualizar-phpmyadmin <versión> o
    --todas.

1.37.0 (20 oct 2026)
- Seguridad (tercer repaso, tras una auditoría completa):
  * /opt vuelve a ser del administrador: el PHP de una web ya no puede
    cambiar /opt/lampp ni /opt/lvm-instalador para que lo siguiente que
    se arranque con sudo sea suyo. Tus carpetas de dentro no cambian.
  * Aplicar vhosts y /etc/hosts: la copia se lee una sola vez a una
    carpeta de root y se comprueba y escribe esa misma. En los vhosts
    ya no se admiten Define ni variables, y los registros solo pueden ir
    a un fichero de logs.
  * Actualizar: el ayudante copia el paquete a una carpeta de root y
    comprueba allí su huella SHA-256 (la que se te ha mostrado), sus
    ficheros y sus scripts de instalación.
  * Todas las versiones quedan solo para este equipo (también las que
    no están montadas). Si una no se puede proteger, no se arranca.
    Versiones avisa de las que faltan, con el botón Protegerlas.
  * phpMyAdmin solo desde localhost, sin su asistente setup. Los .env y
    los .git de los proyectos ya no se ven por el navegador. Dominios
    desconocidos rechazados también por https.
  * Los volcados se cargan con un usuario temporal que solo puede tocar
    su base (sin DEFINER). Un volcado de una web comprometida no puede
    cambiar otras bases, crear usuarios ni leer o escribir ficheros.
  * MariaDB de XAMPP sin el usuario anónimo ni los permisos de las bases
    test. FTP de XAMPP sin el usuario daemon con la contraseña xampp.
  * El dominio de una tienda que viene de su base solo se falsea si se
    parece al nombre de la carpeta (o ya tiene su vhost).
  * Escrituras como root en los proyectos sin seguir enlaces, descargas
    solo por https, versiones de internet comprobadas, registros solo
    para tu usuario y la ventana sin fichero ventana.py en tu carpeta.
  * Corregido: con dos cambios en httpd.conf (Listen y el vhost de los
    dominios desconocidos) se perdía el primero.

1.36.0 (20 oct 2026)
- Diálogos con más aire: más separación entre textos, campos y
  opciones, y campos algo más altos. En todos los que abre la ventana.
  * Elegir la versión de un proyecto: cada versión es una opción
    separada, con la fecha de su base de datos debajo.

1.35.1 (20 oct 2026)
- Contraseña de administrador: ventana nueva con más aire, como la de
  autorización del sistema: el icono de la aplicación con un candado,
  el texto centrado, un campo más estrecho y más alto y botones grandes.

1.35.0 (20 oct 2026)
- Ventana con los apartados en una barra a la izquierda, como
  Configuración de Ubuntu.
- Cada apartado lleva su icono: los logotipos de PHP, Apache, MariaDB,
  phpMyAdmin, Perl, XAMPP, WordPress y PrestaShop (de Simple Icons, en
  el color de cada marca) o un símbolo del tema.
  * También los componentes de cada versión y los proyectos de Cargar
    proyecto y de Hosts (WordPress o PrestaShop).
- Servicios: una tarjeta por servicio con su logotipo, su estado, sus
  puertos y botones con texto (Reiniciar, Parar, Arrancar). Arriba,
  cuántos están en marcha y «Solo desde este equipo».

1.34.0 (20 oct 2026)
- Cargar proyecto: va en un contenedor hundido, con su título dentro,
  el buscador más grande y más separación con la versión activa.
  * En «Cargado ahora:» solo el proyecto va en verde (el vhost y la
    flecha, en el color normal).
  * El botón «Abrir web.local» es verde con letras blancas.
- Botones: al pasar el ratón sale la mano y cambian un poco de color,
  con una transición corta.

1.33.1 (20 oct 2026)
- Cargar proyecto: botón «Abrir Web.local» (borde y letras verdes) a
  la derecha del proyecto cargado. Abre el vhost en el navegador.

1.33.0 (20 oct 2026)
- Seguridad: una web que visites ya no puede leer phpMyAdmin ni tus
  proyectos desde el navegador haciendo que su dominio apunte a
  127.0.0.1 (DNS rebinding).
  * Nuevo primer vhost del puerto 80 (lvm-dominio-desconocido.conf):
    los dominios que no tienen vhost reciben un 403. Solo pasan localhost, 127.0.0.1 y [::1].
  * web.local y los dominios falseados funcionan igual que antes.
  * La dirección localhost muestra ahora la carpeta htdocs (antes salía
    el proyecto de web.local). phpMyAdmin sigue en localhost/phpmyadmin.
  * Se añade al montar cada versión (o con lvm-instalador asegurar) y
    ya viene en las versiones nuevas.

1.32.0 (20 oct 2026)
- Novedades: la lista de cambios se ve con formato (Markdown): cada
  versión con su título y su fecha, viñetas con sangría, el tema de
  cada cambio en negrita y las rutas y los ficheros en letra de código.
  lvm-instalador novedades la saca en Markdown.
- Se han puesto las tildes que faltaban en la lista de cambios.

1.31.0 (20 oct 2026)
- Seguridad (segundo repaso):
  * Instaladores de XAMPP: se comprueba su sha256, fijada en el
    script, además del md5 (con el md5 solo se puede fabricar otro
    fichero que de lo mismo).
  * ProFTPD: solo se instalan parches que publican su .sha256 (si el
    último no lo tiene, se usa el anterior en vez de fallar).
  * Una rama de PHP más vieja o desconocida ya no recibe sin avisar
    la pila de la última; una más nueva avisa de que no esta probada.
  * XAMPP: los ficheros de lib/php y licenses que podía cambiar
    cualquier usuario pasan a ser solo de root, y temp (sesiones de
    PHP) lleva el bit pegajoso. Al activar la versión o al cerrarla a
    la red; no hace falta reiniciar.
  * Paquete: depende también de sudo, openssl y binutils.

1.30.6 (20 oct 2026)
- Buscar actualizaciones: no encontraba los paquetes 1.30.3 y más
  nuevos (traen el fichero de polkit del mensaje en español, que no
  estaba entre los ficheros admitidos) y decía que no había ninguno.

1.30.5 (20 oct 2026)
- Cargar proyecto: en «Cargado ahora:» el nombre del proyecto va en
  negrita.

1.30.4 (20 oct 2026)
- Cargar proyecto: si la base del proyecto esta en varias versiones,
  la pregunta es «¿Qué versión del proyecto y de PHP quieres
  cargar?» y cada opción muestra la fecha de su copia de la base.
- «Cargado ahora:» va en gris y sin negrita; el proyecto, en verde.

1.30.3 (20 oct 2026)
- Actualizar: la contraseña se pide con un mensaje en español
  («Para instalar la versión nueva de LAMPP Version Manager hace
  falta tu contraseña») en vez del aviso en inglés de pkexec. Se ve a
  partir de la siguiente actualización.

1.30.2 (20 oct 2026)
- Versiones, Cargar proyecto: «Cargado ahora: …» sale en verde y en
  negrita, para ver de un vistazo que proyecto esta activo.

1.30.1 (20 oct 2026)
- Menú (☰): Buscar actualizaciones. Busca en Descargas un
  lvm-instalador_*.deb más nuevo y, si lo hay, muestra su fecha y su
  huella y lo instala (pide la contraseña). Al abrir la ventana ya no
  se busca solo.

1.30.0 (20 oct 2026)
- Versiones: bloque nuevo, Cargar proyecto, el primero de la pestaña.
  Se busca la carpeta del proyecto en /opt/htdocs (se ve también el
  que esta cargado ahora) y se pulsa Cargar: el vhost (web.local)
  apunta a su carpeta y se monta la versión de PHP donde esta su base
  de datos. Si la base esta en varias versiones, o en ninguna, se
  pregunta cual montar (se propone la activa o la de su .php-version).
- El aviso «Se puede entrar desde otros equipos de la red» ya solo
  sale en la pestaña Servicios.

1.29.0 (20 oct 2026)
- Seguridad: Apache, MariaDB y el FTP solo aceptan conexiones de este
  equipo (127.0.0.1 y ::1). XAMPP los deja abiertos a toda la red:
  cualquier equipo de la oficina podía ver los proyectos y entrar por
  FTP con el usuario daemon y la contraseña xampp. Se cambia solo lo
  que falta al montar, arrancar o registrar una versión (copia en
  ~/lvm-copias); las pilas nuevas ya se instalan así. Si algo sigue
  abierto, la pestaña Versiones avisa con un botón «Cerrar a la red».
  En la terminal: lvm-instalador asegurar.
- Pestaña nueva, Servicios (como el panel de XAMPP): Apache, MariaDB y
  el FTP de la versión montada, si están en marcha y si se puede
  entrar desde la red, con botones para arrancar, parar o reiniciar
  cada uno. El FTP ya no arranca con la versión: se arranca aquí
  cuando haga falta. En la terminal: lvm-instalador servicio
  apache|mariadb|ftp arrancar|parar|reiniciar.
- Subir una base: el volcado solo puede llevar SQL. Un .sql manipulado
  ya no puede ejecutar programas en el equipo (\! orden, system) ni
  leer sus ficheros. La línea del modo sandbox se sigue quitando.
- Los vhosts vuelven a ser del administrador (Apache los lee como root
  al arrancar). Editar vhosts abre una copia; al pulsar Aplicar se
  comprueba, se guarda la anterior en ~/lvm-copias, se escribe con la
  contraseña y se recarga Apache. Si Apache no la acepta, se deja
  como estaba. No se admiten ordenes que cambien todo Apache
  (LoadModule, Include, registros con |orden...).
- wp-config.php, parameters.php y var/cache: si en un proyecto son
  enlaces a otra carpeta, no se tocan (con la contraseña se podria
  escribir o borrar un fichero del sistema). Los nombres de bases,
  prefijos y carpetas que traen los proyectos se comprueban antes de
  usarlos en consultas o en los vhosts.
- La contraseña de administrador solo se envia si la pide sudo.
- Actualizar con un .deb de Descargas: ya no se ofrece solo al abrir;
  se busca desde Herramientas y se muestra su fecha y su huella.
- ~/lvm-copias y ~/.lvm-instalador (copias de bases y configuraciones
  de los proyectos) solo son accesibles para tu usuario.

1.28.1 (19 oct 2026)
- Subir una base de datos: el desplegable Proyecto es tan ancho como
  el nombre de carpeta más largo, para verlo entero al elegirlo.
- Al elegir la base se propone el proyecto que se llama como ella
  (wp_mitienda -> wordpress-mitienda, ps_mitienda ->
  prestashop-mitienda), si no hay uno recordado o que ya la use.
  Si se cambia a mano, se respeta.

1.28.0 (19 oct 2026)
- Bases de datos: cada base lleva debajo la fecha y la hora en que se
  importo y su antiguedad (hace 3 días, hace 4 meses...), en la lista
  de cada versión y en el buscador. Las que se suben con la aplicación
  guardan la fecha exacta en ~/.lvm-instalador/importaciones; para las
  demas se muestra cuando cambiaron por última vez sus tablas (al
  importarlas desde phpMyAdmin, por ejemplo), que se ve aunque su
  MariaDB este parado.

1.27.1 (19 oct 2026)
- Tiendas PrestaShop, lo mismo que WordPress en la 1.27.0: al subirle
  una base con Proyecto elegido, y al cargarla si se ha volcado encima
  el código de produccion, su app/config/parameters.php (o
  config/settings.inc.php en las 1.6) pasa a usar la base de la
  carpeta y su prefijo; si sus datos no entran en el MariaDB local,
  root y localhost. El anterior queda en ~/lvm-copias y se vacia la
  cache.
- El wp-config.php que se crea o se rehace lleva WP_SITEURL y WP_HOME
  con la dirección local del proyecto: la del vhost de los proyectos
  tal y como este configurado (https://web.local, http://localhost...)
  o, si el proyecto tiene dominio propio (pestaña Hosts), su dominio.
  Si ya las tiene, se cambia su valor; si no, se añaden delante de los
  datos de la base.

1.27.0 (19 oct 2026)
- Al subir una base de datos, la ventana de la carga termina con un
  check verde grande y el título en verde (antes solo ponia
  Terminado en gris). Igual en el resto de tareas que terminan bien.
- Subir una base de datos: nuevo campo Proyecto. Si es la base nueva de
  un proyecto, se elige su carpeta (se propone sola si se sabe) y la
  base pasa a ser la suya. Si es un WordPress, su wp-config.php se
  rehace con la plantilla de este equipo (la copia del último
  wp-config.php que funciono en local) cambiando solo la base y, si
  hace falta, el prefijo de las tablas. Comando: importar-bd ...
  --proyecto <carpeta>.
- Cargar proyecto en un WordPress con el código de produccion pegado
  encima: comprueba que wp-config.php usa la base asociada a la
  carpeta y que entra en el MariaDB local. Si no, lo rehace con la
  plantilla (sin plantilla: el mismo fichero con root y localhost; sin
  wp-config.php: wp-config-sample.php con claves nuevas). El anterior
  queda en ~/lvm-copias. Comando: wp-config <carpeta> [base].
- La base con la que se carga un proyecto queda asociada a su carpeta.
- La base de cada proyecto ya no se lee de las líneas comentadas de
  wp-config.php (// define( 'DB_NAME', ... )).

1.26.0 (19 oct 2026)
- Tiendas PrestaShop recien clonadas: su app/config/parameters.php no
  va en el repositorio y quedaba vacio (\"install\" directory is
  missing). Cargar proyecto lo crea con la base cargada en local (la
  del buscador, la recordada o ps_<final de la carpeta>), el prefijo de
  sus tablas y claves nuevas, y guarda una copia en
  ~/.lvm-instalador/prestashop para reponerla igual si se pierde. Si ya
  tiene base, no se toca. Ahora se reconoce como tienda aunque no tenga
  configuración, por sus carpetas o por \"prestashop\" en el nombre.
- La primera vez que se carga una tienda (y al crear su parameters.php)
  se vacia su var/cache, que en las 1.7 da error 500 con la cache de
  otro equipo. Si no tiene var/cache no pasa nada.
- Bases de datos: botón para vaciar la cache de la tienda en las bases
  ps_ (lista y buscador). Comando: vaciar-cache <carpeta> | --bd <base>.
- Los vhosts que se crean llevan ServerAdmin con tu correo (el de git,
  user.email; si no hay, usuario@localhost).

1.25.1 (13 oct 2026)
- Hosts, Nuevo proyecto: los campos de carpeta y base de datos tienen un
  ancho fijo, como los de Bases de datos (los nombres largos se cortan
  con ...). La lista de carpetas ya no lleva el dominio al lado: si la
  carpeta elegida ya tiene uno, se indica debajo de Carpeta. La pestaña
  ya no se ensancha.

1.25.0 (13 oct 2026)
- La pestaña Instalar pasa a Versiones, debajo de Instaladas, con el
  título Instalar nuevas versiones de PHP. La ventana queda con cuatro
  pestañas: Versiones, Bases de datos, Hosts y Herramientas.
- Los textos explicativos bajo los títulos de cada bloque se cambian
  por un símbolo de información junto al título: al pasar el raton por
  encima se muestra la explicacion.

1.24.0 (13 oct 2026)
- Hosts, Nuevo proyecto con dominio falseado: la carpeta se elige de una
  lista con las de /opt/htdocs (por ejemplo, la de un git clone; las que
  ya tienen dominio lo indican) o se crea una nueva con +. La base de
  datos, igual: las de la versión activa, una nueva con + o ninguna. Si
  la carpeta trae su configuración (wp-config.php, PrestaShop, .env), se
  propone su base de datos.
- Herramientas: Registro de errores muestra solo /opt/lampp/logs/error_log.
  Nuevo Comandos de lvm-instalador: todos los comandos y que hace cada
  uno (lo mismo que lvm-instalador --ayuda, ahora completo y por temas).

1.23.0 (13 oct 2026)
- Solo la versión montada queda en memoria. Al montar otra, al pulsar
  Parar o al parar desde la terminal, se comprueba que no quede ningún
  proceso de LAMPP (Apache, MariaDB, ProFTPD, PHP-FPM) y se cierran los
  que sigan vivos: primero de forma normal (MariaDB guarda todo antes
  de salir) y, si no hacen caso, a la fuerza. Antes de arrancar se
  cierran los de otras versiones, que ocuparian los puertos.
  Venia del lvm original: el lampp de XAMPP solo cierra lo que esta en
  sus .pid, y todos los procesos se llaman /opt/lampp/bin/... sea cual
  sea la versión, así que los que se quedaban no se distinguian.
- Versiones avisa si hay procesos de otras versiones en memoria, con un
  botón para cerrarlos. Comandos: lvm-instalador procesos (de que
  versión es cada uno) y lvm-instalador cerrar-procesos [--todos].

1.22.0 (13 oct 2026)
- Hosts: Nuevo proyecto con dominio falseado. Con el dominio y la base
  de datos de produccion: crea la carpeta en /opt/htdocs, su vhost http
  y https con certificado, la base vacia en la versión activa y falsea
  el dominio, para construirlo en local y subirlo después tal cual.
  Cargar proyecto vuelve a falsear su dominio. Comando:
  lvm-instalador nuevo-dominio <dominio> <carpeta> [base].
- Herramientas: Registros de errores de la versión montada (error_log
  y los de los vhosts), con Ver el final (las últimas líneas, sin
  abrir ficheros enormes) y Abrir. Registros pasa a llamarse Registros
  de instalaciones. Se quita el panel en la terminal (sigue en el menú).
- Los certificados nuevos son CA:FALSE (Apache ya no avisa con AH01906).

1.21.0 (13 oct 2026)
- Tiendas PrestaShop: al cargar el proyecto se lee su dominio de la base
  (tabla shop_url) y se crea lo que falte, como en el manual de XAMPP:
  su certificado autofirmado en /etc/ssl y su vhost http y https en
  /opt/config/httpd-vhosts.conf (con copia en ~/lvm-copias). Lo que ya
  existe no se toca. Su dominio se falsea en /etc/hosts (127.0.0.1).
- Al cargar cualquier otro proyecto, los dominios de los vhosts dejan
  de estar falseados y vuelven a llevar a la web real. localhost,
  web.local y el nombre del equipo no se tocan nunca.
- Pestaña nueva, Hosts: el dominio falseado arriba, con un interruptor
  encendido y el botón Abrir; debajo, los demas dominios de los vhosts
  con su interruptor para falsearlos o no a mano.
  Comando: lvm-instalador hosts-falsear <dominio> si|no.
- Apache con tu usuario (User/Group, como en el manual): al cargar un
  proyecto y al registrar un XAMPP se añade si la versión no lo tiene.
  Al registrar un XAMPP también se activan los vhosts y /opt/htdocs
  pasa a ser tuyo si no lo era.

1.20.0 (8 oct 2026)
- Pestaña nueva, Herramientas (la última), con lo que se usa de vez en
  cuando: editar vhosts y hosts, registrar un XAMPP de /opt/lampp, abrir
  las carpetas de proyectos, copias y registros, buscar un .deb más
  nuevo en Descargas, volver a crear el icono del menú, el panel en la
  terminal, Novedades y Acerca de. El menú sigue teniendo lo de siempre.

1.19.0 (8 oct 2026)
- Editar vhosts pasa al menú (debajo de Abrir phpMyAdmin), junto a uno
  nuevo, Editar hosts: abre una copia de /etc/hosts en el editor y, al
  pulsar Aplicar, la escribe con sudo (el anterior se guarda en
  ~/lvm-copias; no deja guardar uno sin la línea de localhost).
  Comando: lvm-instalador hosts.
- Versión activa: arrancar en verde, reiniciar en azul y parar en rojo.
- XAMPP y Pila propia, en gris como el resto del texto de la versión.
- Las bases de datos se descargan en .zip (un .sql dentro); se pueden
  volver a cargar tal cual. exportar-bd acepta .zip, .sql y .sql.gz.
- Buscador de bases: un punto verde marca las de la versión activa (ya
  no pone Activa) y no hay botón Activar. Cargar proyecto lo carga
  directamente en la versión de esa base; si hay que cambiar de PHP,
  avisa antes de parar la actual y activar la del proyecto.
- Instalar: Estable, Solo seguridad y Sin soporte son texto de color,
  sin fondo.

1.18.0 (8 oct 2026)
- Botón Editar vhosts en la versión activa (pestaña Versiones): abre
  /opt/lampp/etc/extra/httpd-vhosts.conf con el editor de textos. Si el
  fichero es de root, pide la contraseña una vez y lo hace tuyo para
  poder guardarlo. Después, Reiniciar aplica los cambios.
- Comando nuevo: lvm-instalador vhosts (lo abre en la terminal).

1.17.1 (8 oct 2026)
- Acerca de y Novedades vuelven a mostrar su texto: en la 1.17.0 unas
  comillas sin escapar cortaban el texto y salia un error de la línea
  3732 en cada comando.
- El empaquetador del .deb comprueba que el script no da errores al
  cargarse y que Novedades empieza por la versión del paquete.

1.17.0 (8 oct 2026)
- Actualizar con un .deb: al abrir la ventana, si en Descargas hay un
  lvm-instalador_<version>_all.deb más nuevo que la versión instalada,
  ofrece \"Actualizar a la <version>\". Pide la contraseña en una ventana
  (pkexec), lo instala y vuelve a abrir la ventana con la versión nueva.
  El Centro de aplicaciones no ofrece actualizar un .deb suelto.

1.16.0 (8 oct 2026)
- Cargar proyecto sin vhost para proyectos (equipos sin web.local): ya no
  se queda en un aviso. Crea el vhost web.local (http y https, sin cache
  en el navegador) en /opt/config/httpd-vhosts.conf, su certificado
  autofirmado en /opt/config/ssl y su línea en /etc/hosts, y lo apunta al
  proyecto. La ventana lo explica antes de cargar.
- Dialogos más anchos: el texto ya no se parte en una columna estrecha.
- Acerca de: solo el nombre, la versión, que es (gestor de paquetes
  Apache, MariaDB, PHP, Perl, phpMyAdmin y ProFTPD al estilo XAMPP de
  forma independiente), la firma y el año.
- Novedades: ventana más grande y solo con la lista de cambios (comando
  lvm-instalador novedades).

1.15.2 (8 oct 2026)
- La ventana se abre con el alto necesario para ver entera la pestaña
  Bases de datos (sin pasar del alto de la pantalla): lee los datos
  antes de mostrarse y mide esa pestaña.

1.15.1 (8 oct 2026)
- Cargar proyecto recarga Apache (recarga suave, menos de un segundo) si
  no cambia de versión: cada proceso de PHP recordaba durante 120 s a
  donde apuntaba web.local y seguia sirviendo el proyecto anterior.

1.15.0 (8 oct 2026)
- Buscador de bases de datos: botón \"Cargar proyecto\". Busca la carpeta
  de /opt/htdocs cuya configuración (wp-config.php, PrestaShop o .env)
  usa esa base, activa su versión de PHP y apunta el enlace del vhost
  (web.local) a esa carpeta. Si hay varias carpetas o ninguna, la eliges
  tu y se recuerda (~/.lvm-instalador/proyectos). Si la base esta en
  varias versiones o el .php-version del proyecto pide otra, pregunta
  cual montar. Comando: cargar-proyecto <carpeta> [version].
- \"Activa\" ya no parece un botón: es texto verde junto al nombre de la
  base de datos y de la versión activa.

1.14.0 (8 oct 2026)
- Bases de datos: buscador que filtra mientras escribes y dice en que
  versión (y con que PHP) esta cada base, con un botón para activarla o
  para elegirla como destino si ya es la activa.
- Al cargar una copia en una base que también existe en otra versión,
  avisa de donde esta y pregunta si cargarla también en la activa. Al
  crear una base con un nombre que ya existe en otra versión, lo indica.
- Descargar una copia (.sql.gz o .sql) de cualquier base de cualquier
  versión, desde su lista o desde el buscador. Si esa versión no esta en
  marcha, se arranca un MariaDB temporal sin red (pide sudo).
  Comando: exportar-bd <base> <fichero> [version].
- El botón de phpMyAdmin dice \"Abrir phpMyAdmin\".
- La copia previa al borrar una base ya funciona con el MariaDB 10.4 de
  XAMPP (no se piden eventos y, si mysql.proc es de un MariaDB antiguo,
  se copia sin rutinas).

1.13.2 (8 oct 2026)
- Bases de datos: el selector de la base de destino dice \"Elige una
  base de datos\" (como en el Mac) mientras no se ha elegido ninguna.

1.13.1 (8 oct 2026)
- Ventana, \"Otro parche concreto...\": los parches ya se pueden elegir
  (antes la lista no dejaba seleccionar ninguno y \"Añadir\" seguia
  desactivado). La fila elegida se marca en verde; con doble clic se
  añade directamente.

1.13.0 (7 oct 2026)
- Si falla una instalación, la ventana muestra el botón \"Ver el log
  del error\": un informe con el sistema, el compilador, lo que se
  instalaba, el paso que ha fallado, sus primeros errores, el final de
  su log y, si fallo la configuración, lo último de su config.log. Se
  copia entero con \"Copiar todo\" para buscar la solucion. También se
  guarda como informe-error.txt junto a los logs de la compilación.

1.12.0 (7 oct 2026)
- Instalar: cada rama de PHP indica su estado según php.net: Estable
  (correcciones de errores y de seguridad), Solo seguridad (con la
  fecha hasta la que tendrá parches) o Sin soporte. En \"Otro parche
  concreto\" se ve el estado de la rama y cual es el último parche.
- Panel: la misma información en la lista de ramas.

1.11.1 (7 oct 2026)
- Ventana: la pestaña Bases de datos pasa a ser la segunda e Instalar
  la tercera (lo que más se usa va primero).

1.11.0 (7 oct 2026)
- Cargar bases de datos: también desde un .zip (como los que se
  descargan del servidor), que se descomprime al vuelo, sin ocupar
  espacio en disco.
- Las copias que empiezan por /*M!999999\\- enable the sandbox mode */
  (mariadb-dump moderno) ya se cargan: esa línea se quita al vuelo,
  porque el MariaDB de XAMPP no la entiende (\"Unknown command\").

1.10.1 (7 oct 2026)
- Ventana: el botón Parar hace lo mismo que \"lvm disable\": para la
  versión y quita el enlace /opt/lampp, así que php deja de responder
  en la terminal hasta que actives una versión. Sale también con la
  versión activa ya parada.

1.10.0 (7 oct 2026)
- Ventana, pestaña Bases de datos: nuevo apartado \"Subir o actualizar
  una base de datos\". Eliges el fichero .sql o .sql.gz y la base de la
  versión activa, y una barra muestra lo cargado, el tiempo y lo que
  queda, como pv. Opción para vaciar la base antes.
- Crear y borrar bases de datos de la versión activa, con confirmacion.
  Al borrar una base con tablas avisa de que se elimina todo y es
  irreversible, y ofrece guardar antes una copia en ~/lvm-copias (sin
  copia hay que escribir el nombre de la base).
- Comandos importar-bd <fichero> <base> [--crear] [--vaciar],
  crear-bd <base> y borrar-bd <base> [--copia].
- Las bases con guion u otros simbolos en el nombre ya se ven bien
  (antes salian como wp_mi@002dweb).

1.9.1 (7 oct 2026)
- El icono creado por la 1.8 o anteriores abria el panel de la terminal
  en vez de la ventana: ahora abre la ventana.
- Los errores de la ventana abierta desde el menú se guardan en
  ~/.lvm-instalador/ventana.log.
- El acceso del menú funciona aunque la carpeta tenga espacios.

1.9.0 (7 oct 2026)
- Ventana gráfica (GTK 3, desde Ubuntu 20.04): pestañas Versiones,
  Instalar y Bases de datos, barra de progreso y la contraseña de sudo
  en una ventana. El acceso del menú abre la ventana; el panel de la
  terminal sigue con lvm-instalador.
- Comandos nuevos: ventana, arrancar, parar, reiniciar y
  desinstalar <version> --copia.

1.8.1 (7 oct 2026)
- Si el icono estaba anclado en el dock con su nombre antiguo, se cambia
  por el nuevo (el dock seguia abriendo la ruta vieja).

1.8.0 (7 oct 2026)
- El comando vuelve a ser lvm-instalador y el archivo lvm-instalador.sh
  (LAMPP Version Manager). El comando antiguo pvm-instalador se quita.

1.7.0 (7 oct 2026)
- Nuevo nombre: LAMPP Version Manager. El comando sigue siendo
  pvm-instalador.
- \"Acerca de\" explica por que existe: un XAMPP virtual por cada
  versión de PHP, ya que XAMPP no saca versiones nuevas.

1.6.0 (6 oct 2026)
- \"Cambiar la versión activa\" es la primera opción del menú.
- Actualizar: una versión al día no se puede actualizar; avisa en verde.
- Número de versión debajo de la firma y opción \"Acerca de\".

1.5.0 (6 oct 2026)
- Nuevo nombre: PHP Version Manager. Comando pvm-instalador.
- La versión activa aparece en verde en el panel.

1.4.0 (6 oct 2026)
- PHP 7.4 a 8.5 y cualquier parche publicado, en su propia carpeta.
- PHP 7.4 y 8.0 con OpenSSL 1.1.1w; 7.4 a 8.1 con ICU 72.1.

1.3.0 (6 oct 2026)
- Icono de PHP en el menú de aplicaciones y texto de bienvenida.

1.2.0 (5 oct 2026)
- Equipos ARM: MariaDB se compila desde el código fuente.
- Aviso si se acepta la lista sin marcar ninguna versión.

1.1.0 (5 oct 2026)
- Logo y firma; el acceso abre la terminal a 100x32.
- Barra de progreso en verde durante las instalaciones.

1.0.0 (5 oct 2026)
- Pila propia por versión de PHP, sin depender de un XAMPP.
- Actualizar versiones con los últimos parches de su rama.

0.5.0 (5 oct 2026)
- Cada versión de PHP nueva tiene sus propias bases de datos.

0.4.0 (5 oct 2026)
- Tablas con las versiones de todos los componentes.
- Pantalla de bases de datos y desinstalador con copia de seguridad.

0.3.0 (4 oct 2026)
- Instalador independiente con panel: catalogo de XAMPP, PHP nuevos,
  cambio de versión activa, modo simulación y accesos.

0.2.0 (4 oct 2026)
- Asistente por pasos para instalar versiones de PHP.

0.1.0 (4 oct 2026)
- Primera versión: PHP 8.4 con PHP-FPM sobre una copia de XAMPP 8.2.4."

function about_text() {
    echo "$APP_NAME $APP_VERSION\n$SIGNATURE\n\n$ABOUT_TEXT"
}

# Lista de versiones de ABOUT_TEXT en Markdown: «## version · fecha», viñetas (las de «  *», dentro
# de la anterior) en una sola linea, el tema antes de «:» en negrita y rutas y ficheros como codigo
CHANGES_MD_PY='
import re, sys

VERSION = re.compile(r"^(\d+\.\d+\.\d+) \((.+)\)$")
# Rutas (/opt/..., ~/...) y nombres de fichero: en letra de codigo (no lo de detras de https://)
CODE = re.compile(r"(?<![\w`:/])((?:~/|/)[\w.*<>@+-]+(?:/[\w.*<>@+-]*)*|[\w*<>-]+(?:\.[\w*<>-]+)*"
                  r"\.(?:php|conf|cnf|deb|dmg|sql|zip|gz|desktop|policy|md|py|sh|log|pid|run|sha256)\b)")


def inline(text):
    text = CODE.sub(lambda m: "`%s`" % m.group(1), text)
    # Un punto o una coma del final de la frase queda fuera del codigo
    return re.sub(r"`([^`]*?)([.,;:]+)`", r"`\1`\2", text)


def bullet(text, depth):
    # «Tema: explicacion» o «Tema:» -> el tema en negrita
    m = re.match(r"^([^:«`/]{2,45}):(\s+(.*))?$", text)
    if m:
        text = "**%s:**%s" % (m.group(1), " " + m.group(3) if m.group(3) else "")
        return "  " * depth + "- " + text[:text.index(":**") + 3] + inline(text[text.index(":**") + 3:])
    return "  " * depth + "- " + inline(text)


def convert(plain):
    out, item, depth = [], None, 0

    def flush():
        nonlocal item
        if item is not None:
            out.append(bullet(item, depth))
            item = None

    for line in plain.split("\n"):
        m = VERSION.match(line)
        if m:
            flush()
            if out and out[-1] != "":
                out.append("")
            out.append("## %s · %s" % (m.group(1), m.group(2)))
            out.append("")
        elif line.startswith("- "):
            flush()
            item, depth = line[2:].strip(), 0
        elif line.startswith("  * "):
            flush()
            item, depth = line[4:].strip(), 1
        elif line.strip() and item is not None:
            item += " " + line.strip()
        elif not line.strip():
            flush()
        else:
            flush()
            out.append(inline(line.strip()))
    flush()
    return "\n".join(out).strip() + "\n"


sys.stdout.write(convert(sys.stdin.read()))
'

# Solo la lista de versiones con sus cambios, en Markdown (ventana "Novedades")
function changes_text() {
    echo -e "$ABOUT_TEXT" | sed -n '/^VERSIONES$/,$p' | tail -n +3 | python3 -I -c "$CHANGES_MD_PY"
}

function panel_about() {
    ui_msg "$(about_text)"
}

function panel() {
    offer_command_install

    while true; do
        local options=()

        options+=(
            "activar" "Cambiar la version activa"
            "instalar" "Instalar versiones (XAMPP completos y PHP nuevos)"
        )

        if [ -e /opt/lampp ] && [ ! -L /opt/lampp ]; then
            options+=("registrar" "Registrar el XAMPP sin gestionar de /opt/lampp (necesario para instalar XAMPP)")
        fi

        options+=(
            "estado" "Ver versiones instaladas"
            "bases" "Ver bases de datos de cada version"
            "desinstalar" "Desinstalar versiones"
        )

        local dir
        for dir in $(lampp_dirs); do
            if is_fpm_install "$dir"; then
                options+=("actualizar" "Actualizar versiones de PHP")
                break
            fi
        done

        options+=(
            "acerca" "Acerca de (version y cambios)"
            "salir" "Salir"
        )

        local header="Bienvenido al gestor de versiones LAMPP y PHP para Linux.\n"
        header+="Instala nuevas versiones de PHP o activa la que necesites.\n\n"
        # La version activa va en verde (con ventanas la pinta wt encima del texto)
        header+="Version activa: "
        local active=$(active_dir) active_text=""
        if [ -n "$active" ]; then
            active_text="lampp-${active#/opt/lampp-} (PHP $(php_version "$active"))"
            if [ "$UI" == "text" ] && [ -t 2 ]; then
                header+="\033[1;32m$active_text\033[0m"
            else
                header+=$active_text
            fi
        else
            header+="ninguna"
        fi
        [ "$DRY" -eq 1 ] && header+="\nMODO SIMULACION: no se hace ningun cambio"
        header+="\n\n¿Que quieres hacer?"

        # Firma abajo a la derecha de la cabecera, del ancho de la lista de opciones
        local cols=$(tput cols 2> /dev/null || echo 80)
        local sign_w=72
        (( sign_w > cols - 6 )) && sign_w=$(( cols - 6 ))
        if [ "$UI" == "text" ]; then
            header=$(with_signature "$header" $sign_w)
            header+="\n$(printf '%*s' $(( sign_w - ${#APP_VERSION} - 1 > 0 ? sign_w - ${#APP_VERSION} - 1 : 0 )) "")v$APP_VERSION"
        fi

        local choice
        choice=$(WT_GREEN=$active_text ui_menu "$header" "activar" "${options[@]}") || break

        case "$choice" in
            registrar) panel_register ;;
            instalar) panel_install ;;
            activar) panel_use ;;
            estado) ui_msg "$(status_text)" ;;
            bases) panel_databases ;;
            desinstalar) panel_remove ;;
            actualizar) panel_rebuild ;;
            acerca) panel_about ;;
            salir) break ;;
        esac
    done

    [ "$UI" == "whiptail" ] && clear

    return 0
}

