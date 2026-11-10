# ===========================================================================
# Panel
# ===========================================================================

function panel_install() {
    local releases=$(php_releases) supported=$(php_supported) states=$(php_branch_states)
    local items=() branch full sha f note
    local widths="13 8 8 9 9 8 11 14"
    local header=$(fmt_row "$widths" "Instalar" "PHP" "Apache" "MariaDB" "ProFTPD" "Perl" "phpMyAdmin" "PHP (php.net)")

    if [ -z "$releases" ]; then
        ui_msg "No se pudo consultar php.net. Comprueba la conexion a internet."

        return 0
    fi

    [ "$UI" == "whiptail" ] && clear && echo "Consultando las ultimas versiones de cada componente..."
    while read -r branch full sha _; do
        [ -z "$branch" ] && continue
        # (cada version en su carpeta, XAMPP-X.Y.Z: al lado de las que ya haya de la rama)
        { [ -e "$BASE_DIR/XAMPP-$full" ] || php_installed_in "$full" > /dev/null; } && continue
        note=$(branch_state_text "$branch" "$states" "$supported")
        IFS='|' read -r -a f <<< "$(stack_versions "$full")"
        items+=("php:$full" "$(fmt_row "$widths" "PHP $full" "${f[@]}" "$note")")
    done <<< "$releases"

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "Ya tienes instaladas todas las versiones disponibles."

        return 0
    fi

    local text="Marca las versiones que quieres instalar (las que ya tienes no aparecen).\n"
    text+="Cada fila indica la version de cada componente que se instalara.\n\n"
    text+="Cada version tiene su pila propia, sin XAMPP: Apache, PHP, Perl, ProFTPD y MariaDB\n"
    text+="se compilan en tu Mac (unos 20-40 min por version) y tienen sus propias bases de datos.\n"
    text+="Segun php.net: 'estable' recibe correcciones de errores y de seguridad (la mejor para\n"
    text+="proyectos nuevos), 'solo seguridad' solo parches de seguridad y 'sin soporte' ya no\n"
    text+="recibe parches (proyectos antiguos)."

    local selected
    while true; do
        selected=$(ui_table_checklist "$text" "$header" "${items[@]}") || return 0
        selected=$(echo $selected)
        [ -n "$selected" ] && break

        # Aceptar sin marcar nada: la fila resaltada no cuenta, hay que marcarla con Espacio
        ui_msg "No has marcado ninguna version.\n\nMuevete con las flechas hasta la version y pulsa Espacio para marcarla\n(aparece [*] a su izquierda). Despues pulsa Intro para aceptar."
    done

    # Resumen
    local n=$(printf '%s\n' $selected | grep -c .)
    local needed=$(( n * SPACE_STACK_GB ))
    local summary="Se va a instalar:\n\n" item
    summary+="$header\n$(printf '%*s' ${#header} "" | tr ' ' '-')\n"

    for item in $selected; do
        full=${item#php:}
        note=$(branch_state_text "${full%.*}" "$states" "$supported")
        IFS='|' read -r -a f <<< "$(stack_versions "$full")"
        summary+="$(fmt_row "$widths" "PHP $full" "${f[@]}" "$note")\n"
    done

    summary+="\nCarpetas:"
    for item in $selected; do full=${item#php:}; summary+=" $BASE_DIR/XAMPP-$full"; done
    summary+="\n"
    summary+="Se compilan en tu Mac y tienen bases de datos propias y vacias.\n"
    summary+="Homebrew instala las librerias necesarias (no PHP), y se copian dentro de cada version.\n"
    summary+="\nEspacio aproximado: ${needed}G\n"
    summary+="\nLa version activa no cambia. Las nuevas se activan con\n'Cambiar la version activa'."
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se hara ningun cambio."
    summary+="\n\n¿Instalar?"

    check_space "$needed" || return 0

    if other_install_running; then
        ui_msg "Hay otra instalacion en marcha. Espera a que termine."

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

    if official_xampp; then
        ui_msg "$LINK es un XAMPP oficial. Apartalo primero (opcion del panel principal)."

        return 0
    fi

    for dir in $(version_dirs); do
        local mark=""
        [ "$dir" == "$active" ] && mark="activa"
        items+=("$(version_name "$dir")" "$(stack_row "$dir" "$mark")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas."

        return 0
    fi

    local version
    version=$(ui_table_menu "Elige la version que quieres activar.\nSe parara la version activa y se arrancara la elegida." \
        "$(version_name "$active")" "$(stack_header "Estado")" "${items[@]}") || return 0

    if [ "$BASE_DIR/XAMPP-$version" == "$active" ]; then
        ui_yesno "XAMPP-$version ya es la version activa. ¿Reiniciarla?" || return 0
        [ "$UI" == "whiptail" ] && clear
        control_lampp restart
    else
        [ "$UI" == "whiptail" ] && clear
        use_version "$version"
    fi

    [ -t 0 ] && [ "$NO_ASK" != "1" ] && read -p "Pulsa Intro para volver al panel... " _
}

function panel_set_aside() {
    local text="Hay un XAMPP oficial en $LINK.\n\n"
    text+="Este gestor necesita que $LINK sea un enlace a la version activa. Sin borrar nada:\n"
    text+="  1. Se para (si algo sigue en marcha, no se mueve nada).\n"
    text+="  2. Se copian todas sus bases de datos (.zip) en ~/nexum-backups/XAMPP-oficial-<fecha>.\n"
    text+="  3. Se copian sus proyectos a $COMMON/htdocs y sus vhosts al fichero compartido.\n"
    text+="  4. Se mueve a $APPS_DIR/XAMPP-oficial-<fecha>.\n\n"
    text+="Despues, activa una version y carga sus bases (en la ventana, en Configuración).\n"
    text+="Se puede deshacer con Volver al XAMPP oficial.\n\n¿Apartarlo?"

    ui_yesno "$text" || return 0
    [ "$UI" == "whiptail" ] && clear
    set_aside_official
    [ -t 0 ] && [ "$NO_ASK" != "1" ] && read -p "Pulsa Intro para volver al panel... " _
}

function panel_restore_official() {
    local aside=$(ls -d "$APPS_DIR"/XAMPP-oficial-* 2> /dev/null | sort | tail -1)
    ui_yesno "Se para y desactiva la version activa del gestor y $aside\nvuelve a $LINK, y se arranca.\n\nLas versiones del gestor, sus bases de datos y las copias no se tocan.\n\n¿Volver al XAMPP oficial?" || return 0
    [ "$UI" == "whiptail" ] && clear
    restore_official "$aside"
    [ -t 0 ] && [ "$NO_ASK" != "1" ] && read -p "Pulsa Intro para volver al panel... " _
}

function panel_databases() {
    local choice active
    while true; do
        active=$(active_dir)
        local where="ninguna version activa"
        [ -n "$active" ] && where="XAMPP-$(version_name "$active")"
        choice=$(ui_menu "Bases de datos. Cargar, crear y borrar se hace en la version activa ($where)." "${choice:-ver}" \
            "ver" "Ver las bases de datos de cada version" \
            "cargar" "Subir o actualizar una base de datos (fichero .sql, .sql.gz o .zip)" \
            "crear" "Crear una base de datos" \
            "borrar" "Borrar una base de datos") || return 0
        case "$choice" in
            ver) panel_db_list ;;
            cargar) panel_db_import ;;
            crear) panel_db_create ;;
            borrar) panel_db_drop ;;
        esac
    done
}

function panel_db_list() {
    local items=() dir version count active=$(active_dir)
    local widths="10 12 30"

    for dir in $(version_dirs); do
        version=$(version_name "$dir")
        count=$(db_names "$dir" | grep -c .)
        local data="propias"
        [ "$dir" == "$active" ] && data+=" (activa)"
        items+=("$version" "$(fmt_row "$widths" "$version" "$count" "$data")")
    done
    version=""

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas."

        return 0
    fi

    while true; do
        version=$(ui_table_menu "Elige una version para ver sus bases de datos." "${version:-$(version_name "$active")}" \
            "$(fmt_row "$widths" "Version" "BBDD" "De quien son")" "${items[@]}") || return 0

        local cols=$(tput cols 2> /dev/null || echo 80)
        ui_msg "$(databases_text "$version" $(( (cols > 110 ? 110 : cols) - 8 )))"
    done
}

